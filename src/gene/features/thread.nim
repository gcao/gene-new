import tables, std/os
import asyncdispatch, asyncfutures

import ../types
import ../interpreter_base

type
  ExSpawn* = ref object of Expr
    return_value*: bool
    args*: Table[string, Expr]
    body*: seq[Value]

proc thread_handler(thread_id: int) =
  init_app_and_vm_for_thread(thread_id)

  # TODO: VM.app.pkg should be updated to refer to the right package/module where
  # the thread is created from.
  var module = new_module(VM.app.pkg)
  var frame = new_frame(FrModule)
  frame.ns = module.ns
  frame.scope = new_scope()

  # Receive code from my channel
  # .recv() will block until a message is received.
  var msg = Threads[thread_id].channel.recv()

  for k, v in msg.payload.gene_props:
    frame.scope.def_member(k, v)

  # Run code
  var expr = translate(msg.payload.gene_children)
  var r = eval(frame, expr)

  if msg.type == MtRunWithReply:
    # Send result to caller thread thru channel
    var parent_id = Threads[thread_id].parent_id
    var reply = ThreadMessage(
      `type`: MtReply,
      payload: r,
      from_thread_id: VM.thread_id,
      from_message_id: msg.id,
    )
    Threads[parent_id].channel.send(reply)

  # Free resources
  cleanup_thread(thread_id)

proc eval_spawn(frame: Frame, expr: var Expr): Value {.gcsafe.} =
  var e = cast[ExSpawn](expr)

  # 1. Obtain a free thread.
  #    If there is no thread available, wait for one to be available or throw an error ?!
  var child_thread_id = get_free_thread()
  init_thread(child_thread_id, VM.thread_id)
  Threads[child_thread_id].parent_id = VM.thread_id
  Threads[child_thread_id].parent_secret = Threads[VM.thread_id].secret

  # 2. Create thread
  create_thread(Threads[child_thread_id].thread, thread_handler, child_thread_id)

  # 3. Send code to run
  var child_channel = Threads[child_thread_id].channel.addr
  var payload = new_gene_gene()
  payload.gene_children = e.body

  for k, v in e.args.mpairs:
    payload.gene_props[k] = eval(frame, v)

  var msg_type = if e.return_value: MtRunWithReply else: MtRun
  var msg = ThreadMessage(
    id: rand(),
    `type`: msg_type,
    payload: payload,
    from_thread_id: VM.thread_id,
  )
  child_channel[].send(msg)

  if e.return_value:
    result = new_gene_future(new_future[Value]())
    VM.futures[msg.id] = result
  else:
    result = Value(
      kind: VkThread,
      thread_id: child_thread_id,
      thread_secret: Threads[child_thread_id].secret,
    )

proc translate_spawn(value: Value): Expr {.gcsafe.} =
  var r = ExSpawn(
    evaluator: eval_spawn,
    return_value: value.gene_type.is_symbol("spawn_return"),
    body: value.gene_children,
  )
  if value.gene_props.has_key("args"):
    for k, v in value.gene_props["args"].map:
      r.args[k] = translate(v)
  return r

proc thread_parent(frame: Frame, self: Value, args: Value): Value =
  result = Value(
    kind: VkThread,
    thread_id: Threads[VM.thread_id].parent_id,
    thread_secret: Threads[VM.thread_id].parent_secret,
  )

proc thread_join(frame: Frame, self: Value, args: Value): Value =
  Threads[self.thread_id].thread.join_thread()

proc thread_send(frame: Frame, self: Value, args: Value): Value =
  if Threads[self.thread_id].secret != self.thread_secret:
    not_allowed("The receiving thread has ended.")

  var msg_type = if args.gene_props.has_key("reply"): MtSendWithReply else: MtSend
  var msg = ThreadMessage(
    id: rand(),
    `type`: msg_type,
    payload: args.gene_children[0],
    from_thread_id: VM.thread_id,
  )
  var channel = Threads[self.thread_id].channel.addr
  channel[].send(msg)
  if msg_type == MtSendWithReply:
    result = new_gene_future(new_future[Value]())
    VM.futures[msg.id] = result

proc thread_on_message(frame: Frame, self: Value, args: Value): Value =
  VM.thread_callbacks.add(args.gene_children[0])

proc thread_run(frame: Frame, self: Value, args: Value): Value =
  if Threads[self.thread_id].secret != self.thread_secret:
    not_allowed("The receiving thread has ended.")

  var channel = Threads[self.thread_id].channel.addr
  var payload = new_gene_gene()
  payload.gene_children = args.gene_children
  if args.gene_props.has_key("args"):
    for k, v in args.gene_props["args"].map:
      var e = translate(v)
      payload.gene_props[k] = eval(frame, e)

  var msg_type = if args.gene_props.has_key("return"): MtRunWithReply else: MtRun
  var msg = ThreadMessage(
    id: rand(),
    `type`: msg_type,
    payload: payload,
    from_thread_id: VM.thread_id,
  )
  channel[].send(msg)

  if msg_type == MtRunWithReply:
    result = new_gene_future(new_future[Value]())
    VM.futures[msg.id] = result

proc thread_keep_alive(frame: Frame, self: Value, args: Value): Value =
  while true:
    sleep(1)
    check_async_ops_and_channel()
    # TODO: if we receive a message to stop this thread, stop it.

proc message_payload(frame: Frame, self: Value, args: Value): Value =
  self.thread_message.payload

proc message_reply(frame: Frame, self: Value, args: Value): Value =
  var from_thread_id = self.thread_message.from_thread_id
  var from_message_id = self.thread_message.id
  var reply = ThreadMessage(
    `type`: MtReply,
    payload: args.gene_children[0],
    from_message_id: from_message_id,
  )
  Threads[from_thread_id].channel.send(reply)

proc message_mark_handled(frame: Frame, self: Value, args: Value): Value =
  self.thread_message.handled = true

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.thread_class = Value(kind: VkClass, class: new_class("Thread"))
    VM.thread_class.class.parent = VM.object_class.class
    VM.thread_class.def_native_method("parent", thread_parent)
    VM.thread_class.def_native_method("join", thread_join)
    VM.thread_class.def_native_method("send", thread_send)
    VM.thread_class.def_native_method("on_message", thread_on_message)
    VM.thread_class.def_native_macro_method("run", thread_run)
    VM.thread_class.def_native_method("keep_alive", thread_keep_alive)
    VM.gene_ns.ns["Thread"] = VM.thread_class

    VM.thread_message_class = Value(kind: VkClass, class: new_class("ThreadMessage"))
    VM.thread_message_class.class.parent = VM.object_class.class
    VM.thread_message_class.def_native_method("payload", message_payload)
    VM.thread_message_class.def_native_method("reply", message_reply)
    VM.thread_message_class.def_native_method("mark_handled", message_mark_handled)

    let spawn = new_gene_processor(translate_spawn)
    VM.global_ns.ns["spawn"] = spawn
    VM.gene_ns.ns["spawn"] = spawn
    VM.global_ns.ns["spawn_return"] = spawn
    VM.gene_ns.ns["spawn_return"] = spawn

    VM.global_ns.ns["$thread"] = Value(
      kind: VkThread,
      thread_id: VM.thread_id,
      thread_secret: Threads[VM.thread_id].secret,
    )

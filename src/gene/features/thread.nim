import asyncdispatch, asyncfutures

import ../types
import ../interpreter_base

const WAIT_INTERVAL = 5

type
  ExSpawn* = ref object of Expr
    return_value*: bool
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
  var (name, payload) = Threads[thread_id].channel.recv()
  if name != SEND_CODE:
    todo("Expecting code but received " & name)

  # Run code
  var expr = translate(payload)
  var r = eval(frame, expr)

  # Send result to caller thread thru channel
  var parent_id = Threads[thread_id].parent_id
  Threads[parent_id].channel.send((name: SEND_RETURN, payload: r))

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
  child_channel[].send((name: SEND_CODE, payload: new_gene_stream(e.body)))

  if e.return_value:
    # 4. Handle result (by creating an asynchronous Future object)
    var r = new_gene_future(new_future[Value]())
    result = r
    var channel = Threads[VM.thread_id].channel.addr
    add_timer WAIT_INTERVAL, false, proc(fd: AsyncFD): bool =
      let tried = channel[].try_recv()
      if tried.data_available:
        case tried.msg.name:
        of SEND_RETURN:
          r.future.complete(tried.msg.payload)
          # When the callback returns true, does it stop the timer?
          # The answer is Yes.
          return true
        of SEND_MESSAGE:
          var thread = VM.global_ns.ns["$thread"]
          if VM.thread_callbacks.len > 0:
            var callback_args = new_gene_gene()
            callback_args.gene_children.add(tried.msg.payload)
            var frame = Frame()
            for callback in VM.thread_callbacks:
              discard call(frame, thread, callback, callback_args)
        else:
          not_allowed()
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
  return r

proc thread_parent(frame: Frame, self: Value, args: Value): Value =
  result = Value(
    kind: VkThread,
    thread_id: Threads[VM.thread_id].parent_id,
    thread_secret: Threads[VM.thread_id].parent_secret,
  )

proc thread_join(frame: Frame, self: Value, args: Value): Value =
  Threads[self.thread_id].thread.join_thread()

proc thread_send(frame: Frame,self: Value, args: Value): Value =
  if Threads[self.thread_id].secret != self.thread_secret:
    not_allowed("The receiving thread has ended.")
  var channel = Threads[self.thread_id].channel.addr
  channel[].send((name: SEND_MESSAGE, payload: args.gene_children[0]))

proc thread_on_message(frame: Frame, self: Value, args: Value): Value =
  VM.thread_callbacks.add(args.gene_children[0])

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.thread_class = Value(kind: VkClass, class: new_class("Thread"))
    VM.thread_class.class.parent = VM.object_class.class
    VM.thread_class.def_native_method("parent", thread_parent)
    VM.thread_class.def_native_method("join", thread_join)
    VM.thread_class.def_native_method("send", thread_send)
    VM.thread_class.def_native_method("on_message", thread_on_message)
    VM.gene_ns.ns["Thread"] = VM.thread_class

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

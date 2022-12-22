import tables
import asyncdispatch, asyncfutures

import ../types
import ../interpreter_base

type
  ExSpawn* = ref object of Expr
    return_value*: bool
    body*: seq[Value]

# proc thread_handler(body: seq[Value]): Value =
#   init_app_and_vm_for_thread()

#   # TODO: VM.app.pkg should be updated to refer to the right package/module where
#   # the thread is created from.
#   var module = new_module(VM.app.pkg)
#   var frame = new_frame(FrModule)
#   frame.ns = module.ns
#   frame.scope = new_scope()

#   var expr = translate(body)
#   VM.eval(frame, expr)

proc thread_handler(thread_id: int) =
  init_app_and_vm_for_thread()

  # TODO: VM.app.pkg should be updated to refer to the right package/module where
  # the thread is created from.
  var module = new_module(VM.app.pkg)
  var frame = new_frame(FrModule)
  frame.ns = module.ns
  frame.scope = new_scope()

  VM.thread_id = thread_id
  # Receive code from my channel
  var (name, payload) = Threads[thread_id].channel.recv()
  echo $name
  echo $payload
  if name != "code":
    todo("Expecting code but received " & name)

  # Run code
  var expr = translate(payload)
  var r = VM.eval(frame, expr)

  # Send result to caller thread thru channel
  # var parent_id = Threads[i].parent_id
  var parent_id = Threads[thread_id].parent_id
  Threads[parent_id].channel.send(("return", r))

  # Free resources
  cleanup_thread(thread_id)

proc eval_spawn(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value {.gcsafe.} =
  var e = cast[ExSpawn](expr)
  # var r = spawn thread_handler(e.body)
  # return Value(kind: VkThreadResult, thread_result: r)

  # 1. Obtain a free thread.
  #    If there is no thread available, wait for one to be available or throw an error ?!
  var thread_id = get_free_thread()
  init_thread(thread_id, VM.thread_id)

  # 2. Create thread
  create_thread(Threads[thread_id].thread, thread_handler, thread_id)

  # 3. Send code to run
  var channel = Threads[thread_id].channel.addr
  channel[].send((name: "code", payload: new_gene_stream(e.body)))

  # 4. Handle result (by creating an asynchronous Future object)
  var r = new_gene_future(new_future[Value]())
  result = r
  add_timer 1000, false, proc(fd: AsyncFD): bool =
    let tried = channel[].try_recv()
    if tried.data_available:
      echo $tried.msg
      r.future.complete(tried.msg.payload)
      return true

  self.thread_results[thread_id] = result

proc translate_spawn(value: Value): Expr {.gcsafe.} =
  var r = ExSpawn(
    evaluator: eval_spawn,
    return_value: value.gene_type.is_symbol("spawn_return"),
    body: value.gene_children,
  )
  return r

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    let spawn = new_gene_processor(translate_spawn)
    self.global_ns.ns["spawn"] = spawn
    self.gene_ns.ns["spawn"] = spawn
    self.global_ns.ns["spawn_return"] = spawn
    self.gene_ns.ns["spawn_return"] = spawn

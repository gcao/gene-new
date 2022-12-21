import threadpool

import ../types
import ../interpreter_base

type
  ExSpawn* = ref object of Expr
    return_value*: bool
    body*: seq[Value]

proc thread_handler(body: seq[Value]): Value =
  init_app_and_vm_for_thread()

  # TODO: VM.app.pkg should be updated to refer to the right package/module where
  # the thread is created from.
  var module = new_module(VM.app.pkg)
  var frame = new_frame(FrModule)
  frame.ns = module.ns
  frame.scope = new_scope()

  var expr = translate(body)
  VM.eval(frame, expr)

proc eval_spawn(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value {.gcsafe.} =
  var e = cast[ExSpawn](expr)
  var r = spawn thread_handler(e.body)
  return Value(kind: VkThreadResult, thread_result: r)

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

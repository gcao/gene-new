import threadpool

import ../types
import ../interpreter_base

type
  ExSpawn* = ref object of Expr
    return_value*: bool
    body*: seq[Expr]

proc thread_handler() =
  todo()

proc eval_spawn(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  spawn thread_handler()

proc translate_spawn(value: Value): Expr {.gcsafe.} =
  var r = Exspawn(
    evaluator: eval_spawn,
    return_value: value.gene_type.is_symbol("spawn_return"),
  )
  for item in value.gene_children:
    r.body.add translate(item)
  return r

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    let spawn = new_gene_processor(translate_spawn)
    self.global_ns.ns["spawn"] = spawn
    self.gene_ns.ns["spawn"] = spawn
    self.global_ns.ns["spawn_return"] = spawn
    self.gene_ns.ns["spawn_return"] = spawn

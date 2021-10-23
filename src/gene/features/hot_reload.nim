import ../types

type
  ExReload* = ref object of Expr

proc eval_reload(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  if frame.ns.module != nil:
    frame.ns.module.reloadable = true

proc translate_reload(value: Value): Expr =
  ExReload(
    evaluator: eval_reload,
  )

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    self.app.ns["$set_reloadable"] = new_gene_processor(translate_reload)

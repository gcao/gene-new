import ../types
import ../repl
import ../interpreter

type
  ExRepl* = ref object of Expr

proc eval_repl(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  self.repl(frame, eval, true)

proc translate_repl(value: Value): Expr =
  ExRepl(
    evaluator: eval_repl,
  )

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    GLOBAL_NS.ns["repl"] = new_gene_processor(translate_repl)
    GENE_NS.ns["repl"] = GLOBAL_NS.ns["repl"]

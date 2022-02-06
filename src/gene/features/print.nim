import ../types
import ../translators
import ../interpreter_base

type
  ExPrint* = ref object of Expr
    new_line*: bool
    data*: seq[Expr]

proc eval_print(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExPrint](expr)
  for e in expr.data.mitems:
    var v = self.eval(frame, e)
    stdout.write v.to_s & " "
  if expr.new_line:
    echo ""

proc translate_print(value: Value): Expr =
  var r = ExPrint(
    evaluator: eval_print,
    new_line: value.gene_type.symbol == "println",
  )
  for item in value.gene_children:
    r.data.add translate(item)
  return r

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    GLOBAL_NS.ns["print"] = new_gene_processor(translate_print)
    GENE_NS.ns["print"] = GLOBAL_NS.ns["print"]
    GLOBAL_NS.ns["println"] = new_gene_processor(translate_print)
    GENE_NS.ns["println"] = GLOBAL_NS.ns["println"]

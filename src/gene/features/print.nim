import ../types
import ../translators

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
  for item in value.gene_data:
    r.data.add translate(item)
  return r

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    self.app.ns["print"] = new_gene_processor(translate_print)
    self.app.ns["println"] = new_gene_processor(translate_print)

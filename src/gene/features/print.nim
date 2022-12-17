import ../types
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

proc translate_print(value: Value): Expr {.gcsafe.} =
  var r = ExPrint(
    evaluator: eval_print,
    new_line: value.gene_type.str == "println",
  )
  for item in value.gene_children:
    r.data.add translate(item)
  return r

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    self.global_ns.ns["print"] = new_gene_processor(translate_print)
    self.gene_ns.ns["print"] = self.global_ns.ns["print"]
    self.global_ns.ns["println"] = new_gene_processor(translate_print)
    self.gene_ns.ns["println"] = self.global_ns.ns["println"]

import ../types
import ../interpreter_base

type
  ExPrint* = ref object of Expr
    new_line*: bool
    data*: seq[Expr]

proc eval_print(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExPrint](expr)
  for e in expr.data.mitems:
    var v = eval(frame, e)
    stdout.write v.to_s & " "
  if expr.new_line:
    echo ""

proc translate_print(value: Value): Expr {.gcsafe.} =
  var r = ExPrint(
    evaluator: eval_print,
  )
  for item in value.gene_children:
    r.data.add translate(item)
  return r

proc translate_println(value: Value): Expr {.gcsafe.} =
  var r = ExPrint(
    evaluator: eval_print,
    new_line: true,
  )
  for item in value.gene_children:
    r.data.add translate(item)
  return r

proc init*() =
  VmCreatedCallbacks.add proc() =
    let print = new_gene_processor(translate_print)
    VM.gene_ns.ns["print"] = print
    # TODO: tell global namespace to look up print in gene namespace
    VM.global_ns.ns["print"] = print

    let println = new_gene_processor(translate_println)
    VM.gene_ns.ns["println"] = println
    # TODO: tell global namespace to look up println in gene namespace
    VM.global_ns.ns["println"] = println

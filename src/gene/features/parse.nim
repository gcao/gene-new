import ../types
import ../parser
import ../interpreter_base

type
  ExParse* = ref object of Expr
    data*: Expr

proc eval_parse(frame: Frame, expr: var Expr): Value =
  var s = eval(frame, cast[ExParse](expr).data).str
  var vals = read_all(s)
  if vals.len == 0:
    result = Value(kind: VkNil)
  elif vals.len == 1:
    result = vals[0]
  else:
    result = new_gene_stream(vals)

proc translate_parse(value: Value): Expr {.gcsafe.} =
  var r = ExParse(
    evaluator: eval_parse,
    data: translate(value.gene_children[0])
  )
  result = r

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.global_ns.ns["$parse"] = new_gene_processor(translate_parse)

import tables

import ../types
import ../interpreter_base

type
  ExEval* = ref object of Expr
    data*: seq[Expr]

proc eval_eval(frame: Frame, expr: var Expr): Value =
  for e in cast[ExEval](expr).data.mitems:
    var v = eval(frame, e)
    var e2 = translate(v)
    result = eval(frame, e2)

proc translate_eval(value: Value): Expr {.gcsafe.} =
  var e = ExEval(
    evaluator: eval_eval,
  )
  for v in value.gene_children:
    e.data.add(translate(v))
  return e

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["eval"] = translate_eval

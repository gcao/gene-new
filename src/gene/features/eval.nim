import tables

import ../types
import ../translators

type
  ExEval* = ref object of Expr
    data*: seq[Expr]

proc eval_eval(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  for e in cast[ExEval](expr).data.mitems:
    var v = self.eval(frame, e)
    var e2 = translate(v)
    result = self.eval(frame, e2)

proc translate_eval(value: Value): Expr =
  var e = ExEval(
    evaluator: eval_eval,
  )
  for v in value.gene_data:
    e.data.add(translate(v))
  return e

proc init*() =
  GeneTranslators["eval"] = translate_eval

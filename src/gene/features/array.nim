import tables

import ../types
import ../translators
import ../interpreter

type
  ExArray* = ref object of Expr
    data*: seq[Expr]

proc eval_array(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  result = new_gene_vec()
  for e in cast[ExArray](expr).data.mitems:
    result.vec.add(self.eval(frame, e))

proc init*() =
  Translators[VkVector] = proc(value: Value): Expr =
    result = ExArray(
      evaluator: eval_array,
    )
    for v in value.vec:
      cast[ExArray](result).data.add(translate(v))

  # Evaluators[VkExArray.ord] = array_evaluator

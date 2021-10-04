import tables

import ../types
import ../translators

type
  ExArray* = ref object of Expr
    data*: seq[Expr]

proc eval_array(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  result = new_gene_vec()
  for e in cast[ExArray](expr).data.mitems:
    let v = self.eval(frame, e)
    if v == nil:
      discard
    elif v.kind == VkExplode:
      for item in v.explode.vec:
        result.vec.add(item)
    else:
      result.vec.add(v)

proc init*() =
  Translators[VkVector] = proc(value: Value): Expr =
    result = ExArray(
      evaluator: eval_array,
    )
    for v in value.vec:
      cast[ExArray](result).data.add(translate(v))

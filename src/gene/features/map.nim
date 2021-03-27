import tables

import ../map_key
import ../types
import ../translators
import ../interpreter

type
  ExMap* = ref object of Expr
    data*: Table[MapKey, Expr]

proc eval_map(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  result = new_gene_map()
  for k, v in cast[ExMap](expr).data.mpairs:
    result.map[k] = self.eval(frame, v)

proc init*() =
  Translators[VkMap] = proc(value: Value): Expr =
    result = ExMap(
      evaluator: eval_map,
    )
    for k, v in value.map:
      cast[ExMap](result).data[k] = translate(v)

  # Evaluators[VkExMap.ord] = map_evaluator

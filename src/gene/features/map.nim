import tables

import ../map_key
import ../types
import ../interpreter_base

type
  ExMap* = ref object of Expr
    data*: Table[MapKey, Expr]

proc eval_map(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  result = new_gene_map()
  for k, v in cast[ExMap](expr).data.mpairs:
    result.map[k] = self.eval(frame, v)

proc translate_map(value: Value): Expr =
  result = ExMap(
    evaluator: eval_map,
  )
  for k, v in value.map:
    cast[ExMap](result).data[k] = translate(v)

proc init*() =
  Translators[VkMap] = translate_map

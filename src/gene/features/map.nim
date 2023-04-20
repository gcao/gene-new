import tables

import ../types
import ../interpreter_base

type
  ExMap* = ref object of Expr
    data*: Table[string, Expr]

proc eval_map(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  result = new_gene_map()
  for k, v in cast[ExMap](expr).data.mpairs:
    result.map[k] = self.eval(frame, v)

proc translate_map(value: Value): Expr {.gcsafe.} =
  result = ExMap(
    evaluator: eval_map,
  )
  for k, v in value.map:
    cast[ExMap](result).data[k] = translate(v)

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    VM.translators[VkMap] = translate_map

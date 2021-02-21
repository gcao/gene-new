import tables

import ../types
import ../translators
import ../interpreter

proc init*() =
  Translators[VkMap] = proc(value: Value): Value =
    result = Value(kind: VkExMap)
    for k, v in value.map:
      result.ex_map[k] = translate(v)

  Evaluators[VkExMap] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    result = new_gene_map()
    for k, v in expr.ex_map:
      result.map[k] = self.eval(frame, v)

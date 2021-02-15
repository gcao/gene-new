import tables

import ../types
import ../translators
import ../interpreter

proc init*() =
  Translators[VkMap] = proc(v: Value): Value =
    result = Value(kind: VkExMap)
    for k, value in v.map:
      result.ex_map[k] = translate(value)

  Evaluators[VkExMap] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    result = new_gene_map()
    for k, e in expr.ex_map:
      result.map[k] = self.eval(frame, e)

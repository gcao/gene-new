import tables

import ../types
# import ../translators
import ../interpreter

proc init*() =
  # Translators[VkMap] = proc(v: Value): Value =
  #   v

  Evaluators[VkMap] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    result = new_gene_map()
    for k, e in expr.map:
      result.map[k] = self.eval(frame, e)

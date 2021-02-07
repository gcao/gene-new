import tables

import ../types
import ../translators
import ../interpreter

proc init*() =
  Translators[VkVector] = proc(v: Value): Value =
    v

  Evaluators[VkVector] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    result = new_gene_vec()
    for e in expr.vec:
      result.vec.add(self.eval(frame, e))

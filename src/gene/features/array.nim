import tables

import ../types
import ../translators
import ../interpreter

proc init*() =
  Translators[VkVector] = proc(value: Value): Value =
    result = Value(kind: VkExArray)
    for v in value.vec:
      result.ex_array.add(translate(v))

  Evaluators[VkExArray.ord] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    result = new_gene_vec()
    for e in expr.ex_array:
      result.vec.add(self.eval(frame, e))

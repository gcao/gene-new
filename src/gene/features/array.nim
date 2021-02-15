import tables

import ../types
import ../translators
import ../interpreter

proc init*() =
  Translators[VkVector] = proc(v: Value): Value =
    result = Value(kind: VkExArray)
    for item in v.vec:
      result.ex_array.add(translate(item))

  Evaluators[VkExArray] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    result = new_gene_vec()
    for e in expr.ex_array:
      result.vec.add(self.eval(frame, e))

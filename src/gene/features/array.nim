import tables

import ../types
import ../translators
import ../interpreter

proc init*() =
  Translators[VkVector] = proc(value: Value): Value =
    result = Value(kind: VkExArray)
    for v in value.vec:
      result.ex_array.add(translate(v))

  proc array_evaluator(self: VirtualMachine, frame: Frame, expr: var Value): Value =
    result = new_gene_vec()
    for e in expr.ex_array.mitems:
      result.vec.add(self.eval(frame, e))

  Evaluators[VkExArray.ord] = array_evaluator

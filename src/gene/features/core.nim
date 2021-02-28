import tables

import ../types
# import ../translators
import ../interpreter

proc init*() =
  proc group_evaluator(self: VirtualMachine, frame: Frame, expr: Value): Value =
    for e in expr.ex_group:
      result = self.eval(frame, e)

  Evaluators[VkExGroup.ord] = group_evaluator

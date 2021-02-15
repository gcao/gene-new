import tables

import ../types
import ../translators
import ../interpreter

proc init*() =
  Evaluators[VkExGroup] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    for e in expr.ex_group:
      result = self.eval(frame, e)

import tables

import ../types
import ../interpreter

proc init*() =
  Evaluators[VkExNsDef] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    result = self.eval(frame, expr.ex_ns_def_value)
    frame.scope.def_member(expr.ex_ns_def_name, result)

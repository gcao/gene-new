import tables

import ../map_key
import ../types
import ../translators
import ../interpreter

proc init*() =
  GeneTranslators["="] = proc(value: Value): Value =
    Value(
      kind: VkExAssignment,
      ex_assign_name: value.gene_data[0].symbol.to_key,
      ex_assign_value: translate(value.gene_data[1]),
    )

  Evaluators[VkExAssignment] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    if frame.d.scope.has_key(expr.ex_assign_name):
      frame.d.scope[expr.ex_assign_name] = self.eval(frame, expr.ex_assign_value)
    else:
      frame.d.ns[expr.ex_assign_name] = self.eval(frame, expr.ex_assign_value)

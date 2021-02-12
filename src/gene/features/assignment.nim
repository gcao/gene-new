import tables

import ../map_key
import ../types
import ../translators
import ../interpreter

proc init*() =
  GeneTranslators["="] = proc(v: Value): Value =
    Value(
      kind: VkExAssignment,
      ex_assign_name: v.gene_data[0].symbol.to_key,
      ex_assign_value: translate(v.gene_data[1]),
    )

  Evaluators[VkExAssignment] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    if frame.scope.has_key(expr.ex_assign_name):
      frame.scope[expr.ex_assign_name] = self.eval(frame, expr.ex_assign_value)
    else:
      frame.ns[expr.ex_assign_name] = self.eval(frame, expr.ex_assign_value)

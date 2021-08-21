import tables

import ../map_key
import ../types
import ../translators
import ../interpreter

type
  ExAssignment* = ref object of Expr
    name*: MapKey
    value*: Expr

proc eval_assignment(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var name = cast[ExAssignment](expr).name
  var value = cast[ExAssignment](expr).value
  if frame.scope.has_key(name):
    frame.scope[name] = self.eval(frame, value)
  else:
    frame.ns[name] = self.eval(frame, value)

proc init*() =
  GeneTranslators["="] = proc(value: Value): Expr =
    ExAssignment(
      evaluator: eval_assignment,
      name: value.gene_data[0].symbol.to_key,
      value: translate(value.gene_data[1]),
    )

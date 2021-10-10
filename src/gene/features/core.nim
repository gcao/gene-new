import tables

import ../types
import ../translators

type
  ExWith* = ref object of Expr
    self*: Expr
    body*: Expr

proc eval_with(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var old_self = frame.self
  try:
    frame.self = self.eval(frame, cast[ExWith](expr).self)
    return self.eval(frame, cast[ExWith](expr).body)
  finally:
    frame.self = old_self

proc translate_with(value: Value): Expr =
  ExWith(
    evaluator: eval_with,
    self: translate(value.gene_data[0]),
    body: translate(value.gene_data[1..^1]),
  )

proc init*() =
  GeneTranslators["$with"] = translate_with

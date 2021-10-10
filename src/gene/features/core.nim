import tables

import ../types
import ../exprs
import ../translators

type
  ExWith* = ref object of Expr
    self*: Expr
    body*: Expr

proc translate_do(value: Value): Expr =
  var r = ExGroup(
    evaluator: eval_group,
  )
  for item in value.gene_data:
    r.data.add translate(item)
  result = r

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
  GeneTranslators["do"] = translate_do
  GeneTranslators["$with"] = translate_with

import tables

import ../types
import ../translators

type
  ExQuote* = ref object of Expr
    data*: Value

proc eval_quote(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  cast[ExQuote](expr).data

proc translate_quote(value: Value): Expr =
  ExQuote(
    evaluator: eval_quote,
    data: value.quote,
  )

proc init*() =
  Translators[VkQuote] = translate_quote

import tables

import ../types

type
  ExQuote* = ref object of Expr
    data*: Value

proc eval_quote(frame: Frame, expr: var Expr): Value =
  cast[ExQuote](expr).data

proc translate_quote(value: Value): Expr {.gcsafe.} =
  ExQuote(
    evaluator: eval_quote,
    data: value.quote,
  )

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.translators[VkQuote] = translate_quote

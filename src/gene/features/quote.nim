import tables

import ../types
import ../translators
# import ../interpreter

type
  ExQuote* = ref object of Expr
    data*: Value

proc eval_quote(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  cast[ExQuote](expr).data

proc init*() =
  GeneTranslators["quote"] = proc(value: Value): Expr =
    ExQuote(
      evaluator: eval_quote,
      data: value.gene_data[0],
    )

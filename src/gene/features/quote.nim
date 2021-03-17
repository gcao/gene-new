import tables

import ../types
import ../translators
import ../interpreter

proc init*() =
  GeneTranslators["quote"] = proc(value: Value): Value =
    Value(kind: VkExQuote, ex_quote: value.gene_data[0])

  proc quote_evaluator(self: VirtualMachine, frame: Frame, expr: var Value): Value =
    expr.ex_quote

  Evaluators[VkExQuote.ord] = quote_evaluator

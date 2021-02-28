import tables

import ../types
import ../translators
import ../interpreter

proc init*() =
  GeneTranslators["quote"] = proc(value: Value): Value =
    Value(kind: VkExQuote, ex_quote: value.gene_data[0])

  Evaluators[VkExQuote.ord] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    expr.ex_quote

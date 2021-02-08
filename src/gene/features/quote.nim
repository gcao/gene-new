import tables

import ../types
import ../translators
import ../interpreter

proc init*() =
  GeneTranslators["quote"] = proc(v: Value): Value =
    Value(kind: VkExQuote, ex_quote: v.gene_data[0])

  Evaluators[VkExQuote] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    expr.ex_quote

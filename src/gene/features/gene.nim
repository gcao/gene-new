import tables

import ../types
import ../translators
import ../interpreter

proc init*() =
  Translators[VkGene] = proc(v: Value): Value =
    case v.gene_type.kind:
    of VkSymbol:
      case v.gene_type.symbol:
      of "quote":
        result = Value(kind: VkExQuote, ex_quote: v.gene_data[0])
      else:
        result = v
    else:
      result = v

  Evaluators[VkExQuote] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    expr.ex_quote

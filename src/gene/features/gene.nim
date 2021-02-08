import tables

import ../types
import ../translators
import ../interpreter

proc init*() =
  Translators[VkGene] = proc(v: Value): Value =
    case v.gene_type.kind:
    of VkSymbol:
      var translator = GeneTranslators.get_or_default(v.gene_type.symbol, identity)
      translator(v)
    else:
      v

  Evaluators[VkGene] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    var `type` = self.eval(frame, expr.gene_type)
    case `type`.kind:
    of VkString:
      todo()
    else:
      discard

    result = new_gene_gene(`type`)
    for k, v in expr.gene_props:
      result.gene_props[k] = self.eval(frame, v)
    for v in expr.gene_data:
      result.gene_data.add(self.eval(frame, v))

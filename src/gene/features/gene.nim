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

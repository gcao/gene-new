import tables

import ../types
import ../exprs
import ../translators

proc init*() =
  GeneTranslators["do"] = proc(value: Value): Expr =
    var r = ExGroup(
      evaluator: eval_group,
    )
    for item in value.gene_data:
      r.data.add translate(item)
    result = r

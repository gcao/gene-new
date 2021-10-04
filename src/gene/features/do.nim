import tables

import ../types
import ../exprs
import ../translators

proc translate_do(value: Value): Expr =
  var r = ExGroup(
    evaluator: eval_group,
  )
  for item in value.gene_data:
    r.data.add translate(item)
  result = r

proc init*() =
  GeneTranslators["do"] = translate_do

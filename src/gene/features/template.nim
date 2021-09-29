import tables

import ../types
import ../translators
# import ../interpreter

type
  ExRender* = ref object of Expr
    data*: Expr

proc eval_render(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  todo()
  # cast[ExRender](expr).data

proc init*() =
  GeneTranslators["$render"] = proc(value: Value): Expr =
    ExRender(
      evaluator: eval_render,
      data: translate(value.gene_data[0]),
    )

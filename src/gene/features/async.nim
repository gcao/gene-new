import tables

import ../types
import ../translators

type
  ExAsync* = ref object of Expr
    data*: Expr

proc eval_async(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  todo()

proc translate_async(value: Value): Expr =
  ExAsync(
    evaluator: eval_async,
    data: translate(value.gene_data),
  )

proc init*() =
  GeneTranslators["async"] = translate_async

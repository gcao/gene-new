import tables

import ../types
import ../translators

type
  ExTry* = ref object of Expr

proc eval_try(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  todo()

proc translate_try(value: Value): Expr =
  ExTry(
    evaluator: eval_try,
  )

proc init*() =
  GeneTranslators["try"] = translate_try

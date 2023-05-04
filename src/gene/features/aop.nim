import tables

import ../types
# import ../interpreter_base

type
  ExAspect* = ref object of Expr
    name*: string

proc eval_aspect(frame: Frame, expr: var Expr): Value =
  todo()

proc translate_aspect(value: Value): Expr {.gcsafe.} =
  result = ExAspect(
    name: value.gene_children[0].str,
    evaluator: eval_aspect,
  )

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["aspect"] = translate_aspect

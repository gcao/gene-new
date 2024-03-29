import tables

import ../types
import ../interpreter_base

type
  ExRange* = ref object of Expr
    start*: Expr
    `end`*: Expr

proc eval_range*(frame: Frame, expr: var Expr): Value =
  var start = eval(frame, cast[ExRange](expr).start)
  var `end` = eval(frame, cast[ExRange](expr).end)
  new_gene_range(start, `end`)

proc new_ex_range*(start, `end`: Expr): Expr =
  ExRange(
    evaluator: eval_range,
    start: start,
    `end`: `end`,
  )

proc translate_range(value: Value): Expr {.gcsafe.} =
  new_ex_range(translate(value.gene_children[0]), translate(value.gene_children[1]))

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["range"] = translate_range

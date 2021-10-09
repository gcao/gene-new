import tables

import ../types
import ../translators

type
  ExRange* = ref object of Expr
    start*: Expr
    `end`*: Expr

proc eval_range(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var start = self.eval(frame, cast[ExRange](expr).start)
  var `end` = self.eval(frame, cast[ExRange](expr).end)
  new_gene_range(start, `end`)

proc translate_range(value: Value): Expr =
  ExRange(
    evaluator: eval_range,
    start: translate(value.gene_data[0]),
    `end`: translate(value.gene_data[1]),
  )

proc init*() =
  GeneTranslators["range"] = translate_range

import tables

import ../types
import ../interpreter_base

type
  ExCast* = ref object of Expr
    value*: Expr
    class*: Expr
    body: Expr

proc eval_cast(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExCast](expr)
  var v = self.eval(frame, expr.value)
  var class = self.eval(frame, expr.class)
  Value(kind: VkCast, cast_class: class.class, cast_value: v)

proc translate_cast(value: Value): Expr =
  ExCast(
    evaluator: eval_cast,
    value: translate(value.gene_children[0]),
    class: translate(value.gene_children[1]),
    body: translate(value.gene_children[2..^1]),
  )

proc init*() =
  GeneTranslators["cast"] = translate_cast

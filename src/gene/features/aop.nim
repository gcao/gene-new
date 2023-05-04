import tables

import ../types
import ../interpreter_base

type
  # ExAspect* = ref object of Expr
  #   name*: string
  AdviceKind* = enum
    AdBefore
    AdAfter
    AdAround
  ExAdvice* = ref object of Expr
    kind*: AdviceKind
    target*: Expr
    advice*: Expr

# proc eval_aspect(frame: Frame, expr: var Expr): Value =
#   todo()

# proc translate_aspect(value: Value): Expr {.gcsafe.} =
#   result = ExAspect(
#     name: value.gene_children[0].str,
#     evaluator: eval_aspect,
#   )

proc eval_advice(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExAdvice](expr)
  var interception = Interception(
    target: eval(frame, expr.target),
    advice: eval(frame, expr.advice),
  )
  result = Value(kind: VkInterception, interception: interception)

proc translate_advice(value: Value): Expr {.gcsafe.} =
  var e = ExAdvice(
    evaluator: eval_advice,
    target: translate(value.gene_children[0]),
    advice: translate(value.gene_children[1]),
  )
  case value.gene_type.str:
  of "before":
    e.kind = AdBefore
  of "after":
    e.kind = AdAfter
  of "around":
    e.kind = AdAround
  return e

proc init*() =
  VmCreatedCallbacks.add proc() =
    # VM.gene_translators["aspect"] = translate_aspect
    VM.gene_translators["before"] = translate_advice

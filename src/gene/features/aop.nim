import tables

import ../types
import ../interpreter_base

type
  # ExAspect* = ref object of Expr
  #   name*: string

  ExInterception* = ref object of Expr
    kind*: InterceptionKind
    target*: Expr
    logic*: Expr

# proc eval_aspect(frame: Frame, expr: var Expr): Value =
#   todo()

# proc translate_aspect(value: Value): Expr {.gcsafe.} =
#   result = ExAspect(
#     name: value.gene_children[0].str,
#     evaluator: eval_aspect,
#   )

proc eval_interception(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExInterception](expr)
  var interception = Interception(
    target: eval(frame, expr.target),
    kind: expr.kind,
    logic: eval(frame, expr.logic),
  )
  result = Value(kind: VkInterception, interception: interception)

proc translate_interception(value: Value): Expr {.gcsafe.} =
  var e = ExInterception(
    evaluator: eval_interception,
    target: translate(value.gene_children[0]),
    logic: translate(value.gene_children[1]),
  )
  case value.gene_type.str:
  of "before":
    e.kind = IcBefore
  of "after":
    e.kind = IcAfter
  of "around":
    e.kind = IcAround
  return e

proc init*() =
  VmCreatedCallbacks.add proc() =
    # VM.gene_translators["aspect"] = translate_aspect
    VM.gene_translators["before"] = translate_interception
    VM.gene_translators["after"]  = translate_interception
    VM.gene_translators["around"] = translate_interception

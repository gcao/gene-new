import tables

import ../types
import ../interpreter_base

type
  ExArray* = ref object of Expr
    children*: seq[Expr]

proc eval_array(frame: Frame, expr: var Expr): Value =
  result = new_gene_vec()
  for e in cast[ExArray](expr).children.mitems:
    let v = eval(frame, e)
    if v == nil:
      discard
    elif v.kind == VkExplode:
      for item in v.explode.vec:
        result.vec.add(item)
    else:
      result.vec.add(v)

proc translate_array(value: Value): Expr {.gcsafe.} =
  result = ExArray(
    evaluator: eval_array,
  )
  for v in value.vec:
    cast[ExArray](result).children.add(translate(v))

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.translators[VkVector] = translate_array

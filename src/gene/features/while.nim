import tables

import ../types
import ../interpreter_base

type
  ExWhile* = ref object of Expr
    cond*: Expr
    body: seq[Expr]

proc eval_while(frame: Frame, expr: var Expr): Value =
  while true:
    var cond = eval(frame, cast[ExWhile](expr).cond)
    if not cond.bool:
      break
    try:
      for item in cast[ExWhile](expr).body.mitems:
        result = eval(frame, item)
    except Continue:
      discard
    except Break as b:
      result = b.val
      break

proc translate_while(value: Value): Expr {.gcsafe.} =
  var r = ExWhile(
    evaluator: eval_while,
  )
  r.cond = translate(value.gene_children[0])
  for item in value.gene_children[1..^1]:
    r.body.add translate(item)
  result = r

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["while"] = translate_while

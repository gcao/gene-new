import tables

import ../types
import ../translators

type
  ExWhile* = ref object of Expr
    cond*: Expr
    body: seq[Expr]

proc eval_while(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  while true:
    var cond = self.eval(frame, cast[ExWhile](expr).cond)
    if not cond.bool:
      break
    try:
      for item in cast[ExWhile](expr).body.mitems:
        result = self.eval(frame, item)
    except Continue:
      discard
    except Break as b:
      result = b.val
      break

proc translate_while(value: Value): Expr =
  var r = ExWhile(
    evaluator: eval_while,
  )
  r.cond = translate(value.gene_children[0])
  for item in value.gene_children[1..^1]:
    r.body.add translate(item)
  result = r

proc init*() =
  GeneTranslators["while"] = translate_while

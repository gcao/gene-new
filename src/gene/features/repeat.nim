import tables

import ../types
import ../interpreter_base

type
  ExRepeat* = ref object of Expr
    times*: Expr
    code*: seq[Expr]
    index*: Value
    total*: Value

proc eval_repeat(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExRepeat](expr)
  var old_scope = frame.scope
  try:
    var scope = new_scope()
    scope.set_parent(old_scope, old_scope.max)
    frame.scope = scope

    var times = (int)self.eval(frame, expr.times).int
    var i = 0
    if expr.total != nil:
      scope.def_member(expr.total.str, new_gene_int(times))
    if expr.index != nil:
      scope.def_member(expr.index.str, new_gene_int(i))

    while i < times:
      if expr.index != nil:
        scope[expr.index.str] = new_gene_int(i)
      i += 1
      try:
        for item in expr.code.mitems:
          discard self.eval(frame, item)
      except Continue:
        discard
      except Break:
        break
  finally:
    frame.scope = old_scope

proc translate_repeat(value: Value): Expr =
  var r = ExRepeat(
    evaluator: eval_repeat,
    times: translate(value.gene_children[0]),
    index: value.gene_props.get_or_default("index", nil),
    total: value.gene_props.get_or_default("total", nil),
  )
  for item in value.gene_children[1..^1]:
    r.code.add translate(item)
  result = r

proc init*() =
  GeneTranslators["repeat"] = translate_repeat

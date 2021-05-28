import tables

import ../map_key
import ../types
import ../translators
import ../interpreter

type
  ExIf* = ref object of Expr
    cond*: Expr
    then*: Expr
    elifs*: seq[(Expr, Expr)]
    `else`*: Expr

let COND_KEY* = add_key("cond")
let THEN_KEY* = add_key("then")
let ELIF_KEY* = add_key("elif")
let ELSE_KEY* = add_key("else")

proc eval_if(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var expr = ExIf(expr)
  var v = self.eval(frame, expr.cond)
  if v:
    result = self.eval(frame, expr.`then`)
  elif expr.elifs.len > 0:
    for pair in expr.elifs.mitems:
      if self.eval(frame, pair[0]):
        return self.eval(frame, pair[1])
  elif expr.`else` != nil:
    result = self.eval(frame, expr.`else`)

proc init*() =
  GeneTranslators["if"] = proc(value: Value): Expr =
    var r = ExIf(
      evaluator: eval_if,
    )
    r.cond = translate(value.gene_props[COND_KEY])
    r.then = translate(value.gene_props[THEN_KEY])
    if value.gene_props.has_key(ELIF_KEY):
      var elifs = value.gene_props[ELIF_KEY]
      var i = 0
      while i < elifs.vec.len:
        var cond = translate(elifs.vec[i])
        var logic = translate(elifs.vec[i + 1])
        r.elifs.add((cond, logic))
        i += 2
    r.`else` = translate(value.gene_props[ELSE_KEY])
    return r

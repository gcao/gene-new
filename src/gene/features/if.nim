import tables

import ../map_key
import ../types
import ../translators
import ../interpreter

let COND_KEY* = add_key("cond")
let THEN_KEY* = add_key("then")
let ELIF_KEY* = add_key("elif")
let ELSE_KEY* = add_key("else")

proc init*() =
  GeneTranslators["if"] = proc(value: Value): Value =
    result = Value(
      kind: VkExIf,
    )
    result.ex_if_cond = translate(value.gene_props[COND_KEY])
    result.ex_if_then = translate(value.gene_props[THEN_KEY])
    if value.gene_props.has_key(ELIF_KEY):
      var elifs = value.gene_props[ELIF_KEY]
      var i = 0
      while i < elifs.vec.len:
        var cond = translate(elifs.vec[i])
        var logic = translate(elifs.vec[i + 1])
        result.ex_if_elifs.add((cond, logic))
        i += 2
    result.ex_if_else = translate(value.gene_props[ELSE_KEY])

  proc if_evaluator(self: VirtualMachine, frame: Frame, expr: Value): Value =
    var v = self.eval(frame, expr.ex_if_cond)
    if v:
      result = self.eval(frame, expr.ex_if_then)
    elif expr.ex_if_elifs.len > 0:
      for pair in expr.ex_if_elifs:
        if self.eval(frame, pair[0]):
          return self.eval(frame, pair[1])
    elif expr.ex_if_else != nil:
      result = self.eval(frame, expr.ex_if_else)

  Evaluators[VkExIf.ord] = if_evaluator

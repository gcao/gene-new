import tables

import ../map_key
import ../types
import ../exprs
import ../translators
import ../interpreter

type
  ExMatch* = ref object of Expr
    pattern*: Value
    value*: Expr

proc match*(self: VirtualMachine, frame: Frame, pattern: Value, val: Value, mode: MatchMode): Value =
  case pattern.kind:
  of VkSymbol:
    var name = pattern.symbol
    case mode:
    of MatchArgs:
      frame.scope.def_member(name.to_key, val.gene_data[0])
    else:
      frame.scope.def_member(name.to_key, val)
  of VkVector:
    for i in 0..<pattern.vec.len:
      var name = pattern.vec[i].symbol
      if i < val.gene_data.len:
        frame.scope.def_member(name.to_key, val.gene_data[i])
      else:
        frame.scope.def_member(name.to_key, Nil)
  else:
    todo()

proc eval_match(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExMatch](expr)
  result = self.match(frame, expr.pattern, self.eval(frame, expr.value), MatchDefault)

proc translate_match(value: Value): Expr =
  var r = ExMatch(
    evaluator: eval_match,
  )
  r.pattern = value.gene_data[0]
  r.value = translate(value.gene_data[1])
  result = r

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    self.app.ns["match"] = new_gene_processor(translate_match)

import tables

import ../map_key
import ../types
import ../exprs
import ../translators
import ../interpreter

type
  ExSymbol* = ref object of Expr
    name*: MapKey
  ExVar* = ref object of Expr
    name*: MapKey
    value*: Expr

proc eval_symbol_scope(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  frame.scope[ExSymbol(expr).name]

proc eval_symbol_ns(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  frame.ns[ExSymbol(expr).name]

proc eval_symbol(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  result = frame.scope[ExSymbol(expr).name]
  if result == nil:
    expr.evaluator = eval_symbol_ns
    return frame.ns[ExSymbol(expr).name]
  else:
    expr.evaluator = eval_symbol_scope

proc eval_var(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var value = self.eval(frame, ExVar(expr).value)
  frame.scope.def_member(ExVar(expr).name, value)

proc init*() =
  Translators[VkSymbol] = proc(value: Value): Expr =
    ExSymbol(
      evaluator: eval_symbol,
      name: value.symbol.to_key,
    )

  GeneTranslators["var"] = proc(value: Value): Expr =
    var name = value.gene_data[0]
    var v: Expr
    if value.gene_data.len > 1:
      v = translate(value.gene_data[1])
    else:
      v = new_ex_literal(Nil)
    case name.kind:
    of VkSymbol:
      result = ExVar(
        evaluator: eval_var,
        name: name.symbol.to_key,
        value: v,
      )
    else:
      todo($name.kind)

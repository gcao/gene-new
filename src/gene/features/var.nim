import strutils
import tables

import ../map_key
import ../types
import ../exprs
import ../translators

type
  ExVar* = ref object of Expr
    name*: MapKey
    value*: Expr

  ExVarComplex* = ref object of Expr
    first*: MapKey
    rest*: seq[MapKey]
    value*: Expr

let GLOBAL_KEY*               = add_key("global")
let GENE_KEY*                 = add_key("gene")
let GENEX_KEY*                = add_key("genex")

proc eval_symbol_scope(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  frame.scope[cast[ExSymbol](expr).name]

proc eval_symbol_ns(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  frame.ns[cast[ExSymbol](expr).name]

proc eval_symbol(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  result = frame.scope[cast[ExSymbol](expr).name]
  if result == nil:
    expr.evaluator = eval_symbol_ns
    return frame.ns[cast[ExSymbol](expr).name]
  else:
    expr.evaluator = eval_symbol_scope

proc translate_symbol(value: Value): Expr =
  if value.symbol.startsWith("@"):
    return new_ex_get_prop(value.symbol[1..^1])

  case value.symbol:
  of "self":
    result = new_ex_self()
  of "_":
    result = new_ex_literal(Placeholder)
  else:
    result = ExSymbol(
      evaluator: eval_symbol,
      name: value.symbol.to_key,
    )

proc eval_complex_symbol(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var ns: Namespace
  var first = cast[ExComplexSymbol](expr).first
  case first:
  of EMPTY_STRING_KEY:
    ns = frame.ns
  else:
    ns = frame[first].ns

  var is_first = true
  for item in cast[ExComplexSymbol](expr).rest:
    if not is_first:
      is_first = true
      ns = result.ns
    result = ns[item]

proc translate_complex_symbol(value: Value): Expr =
  var r = ExComplexSymbol(
    evaluator: eval_complex_symbol,
    first: value.csymbol.first.to_key(),
  )
  for item in value.csymbol.rest:
    r.rest.add(item.to_key())
  result = r

proc eval_var(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var value = self.eval(frame, cast[ExVar](expr).value)
  frame.scope.def_member(cast[ExVar](expr).name, value)

proc eval_var_complex(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExVarComplex](expr)
  var ns: Namespace
  case e.first:
  of EMPTY_STRING_KEY:
    ns = frame.ns
  else:
    ns = frame[e.first].ns

  if e.rest.len > 1:
    for item in e.rest[0..^2]:
      ns = ns[item].ns

  ns[e.rest[^1]] = self.eval(frame, cast[ExVarComplex](expr).value)

proc translate_var(value: Value): Expr =
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
  of VkComplexSymbol:
    var r = ExVarComplex(
      evaluator: eval_var_complex,
      first: name.csymbol.first.to_key,
      value: v,
    )
    for item in name.csymbol.rest:
      r.rest.add(item.to_key())
    result = r
  else:
    todo($name.kind)

proc init*() =
  Translators[VkSymbol] = translate_symbol
  Translators[VkComplexSymbol] = translate_complex_symbol
  GeneTranslators["var"] = translate_var

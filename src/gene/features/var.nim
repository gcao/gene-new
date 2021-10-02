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

proc eval_var(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var value = self.eval(frame, cast[ExVar](expr).value)
  frame.scope.def_member(cast[ExVar](expr).name, value)

proc eval_var_complex(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExVarComplex](expr)
  var ns: Namespace
  case e.first:
  of EMPTY_STRING_KEY:
    ns = frame.ns
  of GLOBAL_KEY:
    ns = GLOBAL_NS.ns
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
  GeneTranslators["var"] = translate_var

import strutils
import tables

import ../map_key
import ../types
import ../exprs
import ../translators

type
  ExMember* = ref object of Expr
    container*: Expr
    name*: MapKey

  # member of self
  ExMyMember* = ref object of Expr
    name*: MapKey

let NS_EXPR = Expr()
NS_EXPR.evaluator = proc(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  Value(kind: VkNamespace, ns: frame.ns)

proc eval_symbol_scope(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  frame.scope[cast[ExSymbol](expr).name]

proc eval_symbol_ns(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  frame.ns[cast[ExSymbol](expr).name]

# proc eval_symbol(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
#   result = frame.scope[cast[ExSymbol](expr).name]
#   if result == nil:
#     expr.evaluator = eval_symbol_ns
#     return frame.ns[cast[ExSymbol](expr).name]
#   else:
#     expr.evaluator = eval_symbol_scope

proc eval_my_member(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  result = frame.scope[cast[ExMyMember](expr).name]
  if result == nil:
    expr.evaluator = eval_symbol_ns
    return frame.ns[cast[ExMyMember](expr).name]
  else:
    expr.evaluator = eval_symbol_scope

proc eval_member(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var v = self.eval(frame, cast[ExMember](expr).container)
  var key = cast[ExMember](expr).name
  case v.kind:
  of VkNamespace:
    return v.ns.members[key]
  of VkClass:
    return v.class.ns.members[key]
  of VkMixin:
    return v.mixin.ns.members[key]
  else:
    todo()

proc translate*(name: string): Expr {.inline.} =
  if name.startsWith("@"):
    return new_ex_get_prop(name[1..^1])
  if name.endsWith("..."):
    var r = new_ex_explode()
    r.data = translate(new_gene_symbol(name[0..^4]))
    return r

  case name:
  of "self":
    result = new_ex_self()
  of "global":
    result = new_ex_literal(GLOBAL_NS)
  of "_":
    result = new_ex_literal(Placeholder)
  of "$ns":
    result = NS_EXPR
  else:
    result = ExMyMember(
      evaluator: eval_my_member,
      name: name.to_key,
    )

proc translate*(names: seq[string]): Expr =
  if names.len == 1:
    return translate(names[0])
  else:
    var name = names[^1]
    return ExMember(
      evaluator: eval_member,
      container: translate(names[0..^2]),
      name: name.to_key,
    )

proc translate_symbol(value: Value): Expr =
  translate(value.symbol)

proc translate_complex_symbol(value: Value): Expr =
  translate(value.csymbol.parts)

proc init*() =
  Translators[VkSymbol] = translate_symbol
  Translators[VkComplexSymbol] = translate_complex_symbol

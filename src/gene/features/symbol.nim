import strutils, sequtils, tables

import ../map_key
import ../types
import ../interpreter_base
import ./selector

type
  ExSymbol* = ref object of Expr
    name*: MapKey

  ExDefineNsOrScope* = ref object of Expr
    name*: MapKey
    value*: Expr

  ExMember* = ref object of Expr
    container*: Expr
    name*: MapKey

  ExChild* = ref object of Expr
    container*: Expr
    index*: int

  # member of self
  ExMyMember* = ref object of Expr
    name*: MapKey

  ExPackage* = ref object of Expr

let SELF_EXPR = Expr()
SELF_EXPR.evaluator = proc(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  frame.self

let NS_EXPR = Expr()
NS_EXPR.evaluator = proc(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  Value(kind: VkNamespace, ns: frame.ns)

let PKG_EXPR = Expr()
PKG_EXPR.evaluator = proc(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  Value(kind: VkPackage, pkg: frame.ns.package)

proc eval_symbol_scope(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  frame.scope[cast[ExSymbol](expr).name]

proc eval_symbol_ns(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  frame.ns[cast[ExSymbol](expr).name]

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
  return v.get_member(key)

proc eval_child(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var v = self.eval(frame, cast[ExMember](expr).container)
  var i = cast[ExChild](expr).index
  return v.get_child(i)

proc translate*(name: string): Expr {.inline.} =
  if name.startsWith("@"):
    return new_ex_selector(name[1..^1])
  if name.endsWith("..."):
    var r = new_ex_explode()
    r.data = translate(new_gene_symbol(name[0..^4]))
    return r

  case name:
  of "", "self":
    result = SELF_EXPR
  of "global":
    result = new_ex_literal(GLOBAL_NS)
  of "_":
    result = new_ex_literal(Placeholder)
  of "$app":
    result = new_ex_literal(Value(kind: VkApplication, app: VM.app))
  of "$ns":
    result = NS_EXPR
  of "$pkg":
    result = PKG_EXPR
  of "$cmd_args":
    result = new_ex_literal(VM.app.args.map(str_to_gene))
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
    if name.starts_with("."):
      return ExInvoke(
        evaluator: eval_invoke,
        self: translate(names[0..^2]),
        meth: name[1..^1].to_key,
        args: new_ex_arg(),
      )
    else:
      try:
        var index = name.parse_int()
        return ExChild(
          evaluator: eval_child,
          container: translate(names[0..^2]),
          index: index,
        )
      except ValueError:
        return ExMember(
          evaluator: eval_member,
          container: translate(names[0..^2]),
          name: name.to_key,
        )

proc translate_symbol(value: Value): Expr =
  translate(value.str)

proc translate_complex_symbol(value: Value): Expr =
  if value.csymbol[0].starts_with("@"):
    translate_csymbol_selector(value.csymbol)
  else:
    translate(value.csymbol)

proc eval_define_ns_or_scope(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExDefineNsOrScope](expr)
  result = self.eval(frame, expr.value)

  var ns: Namespace
  if frame.kind == FrModule:
    ns = frame.ns
  elif frame.self != nil:
    case frame.self.kind:
    of VkNamespace:
      ns = frame.self.ns
    of VkClass:
      ns = frame.self.class.ns
    of VkMixin:
      ns = frame.self.mixin.ns
    else:
      discard

  if ns == nil:
    frame.scope.def_member(expr.name, result)
    if result.kind == VkFunction:
      # Ensure the function itself can be accessed from its body.
      var fn = result.fn
      fn.parent_scope_max = cast[int](fn.parent_scope_max) + 1
  else:
    ns[expr.name] = result

# For (fn f ...)(macro m ...)(ns n)(class C)(mixin M) etc,
# If self is a Namespace like object (e.g. module, namespace, class, mixin),
#   they are defined as a member on the namespace,
# Else they are defined on the current scope
#
# (fn n/m/f ...) will add f to n/m no matter what n/m is
proc translate_definition*(name: Value, value: Expr): Expr =
  case name.kind:
  of VkSymbol, VkString:
    return ExDefineNsOrScope(
      evaluator: eval_define_ns_or_scope,
      name: name.str.to_key,
      value: value,
    )
  of VkComplexSymbol:
    var e = ExSet(
      evaluator: eval_set,
    )
    e.target = translate(name.csymbol[0..^2])
    e.selector = translate(new_gene_symbol("@" & name.csymbol[^1]))
    e.value = value
    return e
  else:
    todo("translate_definition " & $name)

proc init*() =
  Translators[VkSymbol] = translate_symbol
  Translators[VkComplexSymbol] = translate_complex_symbol

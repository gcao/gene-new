import tables

import ../types
import ../interpreter_base
import ./symbol

type
  ExVar* = ref object of Expr
    container*: Expr
    define_assign*: bool
    name*: string
    value*: Expr

proc eval_var(frame: Frame, expr: var Expr): Value =
  var e = cast[ExVar](expr)
  if e.container == nil:
    if e.define_assign:
      frame.scope.def_member(e.name, Value(kind: VkNil))
      result = eval(frame, e.value)
      if result == nil:
        result = Value(kind: VkNil)
      frame.scope[e.name] = result
    else:
      result = eval(frame, e.value)
      if result == nil:
        result = Value(kind: VkNil)
      frame.scope.def_member(e.name, result)
  else:
    var container = eval(frame, e.container)
    var ns: Namespace
    case container.kind:
    of VkNamespace:
      ns = container.ns
    of VkClass:
      ns = container.class.ns
    of VkMixin:
      ns = container.mixin.ns
    else:
      todo("eval_var " & $container.kind)

    if e.define_assign:
      ns[e.name] = Value(kind: VkNil)
      result = eval(frame, e.value)
      if result == nil:
        result = Value(kind: VkNil)
      ns[e.name] = result
    else:
      result = eval(frame, e.value)
      if result == nil:
        result = Value(kind: VkNil)
      ns[e.name] = result

proc translate_var(value: Value): Expr {.gcsafe.} =
  var name = value.gene_children[0]
  var v: Expr
  if value.gene_children.len > 1:
    v = translate(value.gene_children[1])
  else:
    v = new_ex_literal(Value(kind: VkNil))
  var define_assign = value.gene_props.has_key("define_assign") and value.gene_props.has_key("define_assign")
  case name.kind:
  of VkSymbol:
    result = ExVar(
      evaluator: eval_var,
      define_assign: define_assign,
      name: name.str,
      value: v,
    )
  of VkComplexSymbol:
    result = ExVar(
      evaluator: eval_var,
      define_assign: define_assign,
      container: translate(name.csymbol[0..^2]),
      name: name.csymbol[^1],
      value: v,
    )
  else:
    todo($name.kind)

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["var"] = translate_var

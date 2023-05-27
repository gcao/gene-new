import tables

import ../map_key
import ../types
import ../interpreter_base
import ./symbol

type
  ExVar* = ref object of Expr
    container*: Expr
    name*: MapKey
    value*: Expr

proc eval_var(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExVar](expr)
  if e.container == nil:
    result = self.eval(frame, e.value)
    if result == nil:
      result = Nil
    frame.scope.def_member(e.name, result)
  else:
    var container = self.eval(frame, e.container)
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

    result = self.eval(frame, e.value)
    if result == nil:
      result = Nil
    ns[e.name] = result

proc translate_var(value: Value): Expr =
  var name = value.gene_children[0]
  var v: Expr
  if value.gene_children.len > 1:
    v = translate(value.gene_children[1])
  else:
    v = new_ex_literal(Nil)
  case name.kind:
  of VkSymbol:
    result = ExVar(
      evaluator: eval_var,
      name: name.str.to_key,
      value: v,
    )
  of VkComplexSymbol:
    result = ExVar(
      evaluator: eval_var,
      container: translate(name.csymbol[0..^2]),
      name: name.csymbol[^1].to_key,
      value: v,
    )
  else:
    todo($name.kind)

proc init*() =
  GeneTranslators["var"] = translate_var

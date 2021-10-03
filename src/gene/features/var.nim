import tables

import ../map_key
import ../types
import ../exprs
import ../translators
import ./symbol

type
  ExVar* = ref object of Expr
    container*: Expr
    name*: MapKey
    value*: Expr

proc eval_var(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExVar](expr)
  if e.container == nil:
    frame.scope.def_member(e.name, self.eval(frame, e.value))
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
      todo()

    ns[e.name] = self.eval(frame, e.value)

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
    result = ExVar(
      evaluator: eval_var,
      container: translate(name.csymbol.parts[0..^2]),
      name: name.csymbol.parts[^1].to_key,
      value: v,
    )
  else:
    todo($name.kind)

proc init*() =
  GeneTranslators["var"] = translate_var

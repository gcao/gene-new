import strutils
import tables

import ../map_key
import ../types
import ../exprs
import ../translators
import ../interpreter_base
import ./oop
import ./selector
import ./gene

type
  ExMember* = ref object of Expr
    container*: Expr
    name*: MapKey

  # member of self
  ExMyMember* = ref object of Expr
    name*: MapKey

  ExPackage* = ref object of Expr

let NS_EXPR = Expr()
NS_EXPR.evaluator = proc(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  Value(kind: VkNamespace, ns: frame.ns)

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

proc call_member_missing*(self: VirtualMachine, frame: Frame, obj: Value, target: Value, args: Value): Value =
  var fn_scope = new_scope()
  var new_frame = Frame(ns: target.fn.ns, scope: fn_scope)
  new_frame.parent = frame
  new_frame.self = obj

  self.process_args(new_frame, target.fn.matcher, args)

  if target.fn.body_compiled == nil:
    target.fn.body_compiled = translate(target.fn.body)

  try:
    result = self.eval(new_frame, target.fn.body_compiled)
  except Return as r:
    # return's frame is the same as new_frame(current function's frame)
    if r.frame == new_frame:
      result = r.val
    else:
      raise
  except system.Exception as e:
    if self.repl_on_error:
      result = repl_on_error(self, frame, e)
      discard
    else:
      raise

proc get_member(self: Value, name: MapKey, vm: VirtualMachine, frame: Frame): Value =
  var ns: Namespace
  case self.kind:
  of VkNamespace:
    ns = self.ns
  of VkClass:
    ns = self.class.ns
  of VkMixin:
    ns = self.mixin.ns
  else:
    todo("get_member " & $self.kind)

  if ns.members.has_key(name):
    return ns.members[name]
  elif ns.on_member_missing.len > 0:
    var args = new_gene_gene()
    args.gene_children.add(name.to_s)
    for v in ns.on_member_missing:
      var r = vm.call_member_missing(frame, self, v, args)
      if r != nil:
        return r
  raise new_exception(NotDefinedException, name.to_s & " is not defined")

proc eval_pkg(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  Value(kind: VkPackage, pkg: frame.ns.package)

proc new_ex_package(): Expr =
  return ExPackage(
    evaluator: eval_pkg,
  )

proc eval_member(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var v = self.eval(frame, cast[ExMember](expr).container)
  var key = cast[ExMember](expr).name
  case v.kind:
  of VkNamespace, VkClass, VkMixin:
    return v.get_member(key, self, frame)
  of VkEnum:
    return new_gene_enum_member(v.enum.members[key.to_s])
  else:
    todo("eval_member " & $v.kind)

proc translate*(name: string): Expr {.inline.} =
  if name.startsWith("@"):
    return new_ex_selector(name[1..^1])
  if name.endsWith("..."):
    var r = new_ex_explode()
    r.data = translate(new_gene_symbol(name[0..^4]))
    return r

  case name:
  of "", "self":
    result = new_ex_self()
  of "global":
    result = new_ex_literal(GLOBAL_NS)
  of "_":
    result = new_ex_literal(Placeholder)
  of "$app":
    result = new_ex_literal(Value(kind: VkApplication, app: VM.app))
  of "$ns":
    result = NS_EXPR
  of "$pkg":
    result = new_ex_package()
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
    if name.starts_with("@"):
      var r = ExSelectorInvoker2(
        evaluator: eval_selector_invoker2,
      )
      r.selector = ExSelector2(
        evaluator: eval_selector2,
        parallel_mode: false,
      )
      cast[ExSelector2](r.selector).data.add(handle_item(name[1..^1]))
      r.target = translate(names[0..^2])
      return r
    elif name.starts_with("."):
      return ExInvoke(
        evaluator: eval_invoke,
        self: translate(names[0..^2]),
        meth: name[1..^1].to_key,
        args: new_ex_arg(),
      )
    elif name == "!":
      return ExGene(
        evaluator: eval_gene_init,
        `type`: translate(names[0..^2]),
        args: new_gene_gene(),
      )
    else:
      return ExMember(
        evaluator: eval_member,
        container: translate(names[0..^2]),
        name: name.to_key,
      )

proc translate_symbol(value: Value): Expr =
  translate(value.symbol)

proc translate_complex_symbol(value: Value): Expr =
  if value.csymbol[0].starts_with("@"):
    translate_csymbol_selector(value.csymbol)
  else:
    translate(value.csymbol)

proc init*() =
  Translators[VkSymbol] = translate_symbol
  Translators[VkComplexSymbol] = translate_complex_symbol

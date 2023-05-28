import tables

import ../types
import ../interpreter_base
import ./symbol

type
  ExNamespace* = ref object of Expr
    container*: Expr
    name*: string
    body*: Expr

  ExMemberMissing* = ref object of Expr
    data: Expr

proc eval_ns(frame: Frame, expr: var Expr): Value =
  var e = cast[ExNamespace](expr)
  var ns = new_namespace(frame.ns, e.name)
  result = Value(kind: VkNamespace, ns: ns)
  var container = frame.ns
  if e.container != nil:
    container = eval(frame, e.container).ns
  container[e.name] = result

  var new_frame = new_frame()
  new_frame.ns = ns
  new_frame.scope = new_scope()
  new_frame.self = result
  discard eval(new_frame, e.body)

proc translate_ns(value: Value): Expr {.gcsafe.} =
  var e = ExNamespace(
    evaluator: eval_ns,
    body: translate(value.gene_children[1..^1]),
  )
  var first = value.gene_children[0]
  case first.kind
  of VkSymbol:
    e.name = first.str
  of VkComplexSymbol:
    e.container = translate(first.csymbol[0..^2])
    e.name = first.csymbol[^1]
  else:
    todo()
  result = e

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["ns"] = translate_ns

    VM.namespace_class = Value(kind: VkClass, class: new_class("Namespace"))
    VM.namespace_class.class.parent = VM.object_class.class
    VM.namespace_class.def_native_method "name", proc(frame: Frame, self: Value, args: Value): Value {.name:"ns_name".} =
      self.ns.name
    VM.namespace_class.def_native_method "members", proc(frame: Frame, self: Value, args: Value): Value {.name:"ns_members".} =
      self.ns.get_members()
    VM.namespace_class.def_native_method "member_names", proc(frame: Frame, self: Value, args: Value): Value {.name:"ns_member_names".} =
      self.ns.member_names()
    VM.namespace_class.def_native_method "has_member", proc(frame: Frame, self: Value, args: Value): Value {.name:"ns_has_member".} =
      self.ns.members.has_key(args[0].to_s)
    VM.namespace_class.def_native_method "proxy", proc(frame: Frame, self: Value, args: Value): Value {.name:"ns_proxy".} =
      self.ns.proxy(args.gene_children[0].to_s, args.gene_children[1])
    VM.namespace_class.def_native_method "on_member_missing", on_member_missing
    VM.gene_ns.ns["Namespace"] = VM.namespace_class
    VM.global_ns.ns["Namespace"] = VM.namespace_class

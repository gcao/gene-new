import tables

import ../map_key
import ../types
import ../exprs
import ../translators
import ../interpreter_base

type
  ExNamespace* = ref object of Expr
    container*: Expr
    name*: string
    body*: Expr

  ExMemberMissing* = ref object of Expr
    fn: Function

proc eval_ns(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExNamespace](expr)
  var ns = new_namespace(frame.ns, e.name)
  result = Value(kind: VkNamespace, ns: ns)
  var container = frame.ns
  if e.container != nil:
    container = self.eval(frame, e.container).ns
  container[e.name] = result

  var new_frame = new_frame()
  new_frame.ns = ns
  new_frame.scope = new_scope()
  new_frame.self = result
  discard self.eval(new_frame, e.body)

proc translate_ns(value: Value): Expr =
  var e = ExNamespace(
    evaluator: eval_ns,
    body: translate(value.gene_children[1..^1]),
  )
  var first = value.gene_children[0]
  case first.kind
  of VkSymbol:
    e.name = first.symbol
  of VkComplexSymbol:
    e.container = new_ex_names(first)
    e.name = first.csymbol[^1]
  else:
    todo()
  result = e

proc eval_member_missing(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  result = Value(
    kind: VkFunction,
    fn: cast[ExMemberMissing](expr).fn,
  )
  result.fn.ns = frame.ns
  result.fn.parent_scope = frame.scope
  result.fn.parent_scope_max = frame.scope.max
  frame.ns.member_missing = result

proc translate_member_missing(value: Value): Expr =
  var name = "member_missing"
  var matcher = new_arg_matcher()
  matcher.parse(value.gene_children[0])

  var body: seq[Value] = @[]
  for i in 1..<value.gene_children.len:
    body.add value.gene_children[i]

  body = wrap_with_try(body)
  var fn = new_fn(name, matcher, body)
  fn.async = value.gene_props.get_or_default(ASYNC_KEY, false)

  ExMemberMissing(
    evaluator: eval_member_missing,
    fn: fn,
  )

proc init*() =
  GeneTranslators["ns"] = translate_ns
  GeneTranslators["member_missing"] = translate_member_missing

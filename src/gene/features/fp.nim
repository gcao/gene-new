import tables

import ../types
import ../interpreter_base
import ./symbol

type
  ExFn* = ref object of Expr
    data*: Function

  ExReturn* = ref object of Expr
    data*: Expr

  ExBind* = ref object of Expr
    target*: Expr
    self*: Expr
    # args*: ExArguments

proc eval_fn(frame: Frame, expr: var Expr): Value =
  result = Value(
    kind: VkFunction,
    fn: cast[ExFn](expr).data,
  )
  result.fn.ns = frame.ns
  result.fn.parent_scope = frame.scope
  result.fn.parent_scope_max = frame.scope.max

proc to_function(node: Value): Function {.gcsafe.} =
  var name: string
  var matcher = new_arg_matcher()
  var body_start: int
  case node.gene_type.str:
  of "fnx":
    matcher.parse(node.gene_children[0])
    name = "<unnamed>"
    body_start = 1
  of "fnxx":
    name = "<unnamed>"
    body_start = 0
  else:
    var first = node.gene_children[0]
    case first.kind:
    of VkSymbol, VkString:
      name = first.str
    of VkComplexSymbol:
      name = first.csymbol[^1]
    else:
      todo($first.kind)

    matcher.parse(node.gene_children[1])
    body_start = 2

  var body: seq[Value] = @[]
  for i in body_start..<node.gene_children.len:
    body.add node.gene_children[i]

  body = wrap_with_try(body)
  result = new_fn(name, matcher, body)
  if node.gene_props.has_key("return"):
    result.ret = translate(node.gene_props["return"])
  result.async = node.gene_props.get_or_default("async", false)

proc translate_fn(value: Value): Expr {.gcsafe.} =
  var fn = to_function(value)
  var fn_expr = ExFn(
    evaluator: eval_fn,
    data: fn,
  )
  return translate_definition(value.gene_children[0], fn_expr)

proc translate_fnx(value: Value): Expr {.gcsafe.} =
  var fn = to_function(value)
  ExFn(
    evaluator: eval_fn,
    data: fn,
  )

proc eval_return(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExReturn](expr)
  var r = Return(
    frame: frame,
  )
  if expr.data != nil:
    r.val = eval(frame, expr.data)
  else:
    r.val = Value(kind: VkNil)
  raise r

proc translate_return(value: Value): Expr {.gcsafe.} =
  var expr = ExReturn()
  expr.evaluator = eval_return
  if value.gene_children.len > 0:
    expr.data = translate(value.gene_children[0])
  return expr

proc eval_bind(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExBind](expr)
  var target = eval(frame, expr.target)
  var self = eval(frame, expr.self)
  var bound_fn = BoundFunction(
    target: target,
    self: self,
    # args: args,
  )
  Value(kind: VkBoundFunction, bound_fn: bound_fn)

proc translate_bind(value: Value): Expr {.gcsafe.} =
  var expr = ExBind()
  expr.evaluator = eval_bind
  expr.target = translate(value.gene_children[0])
  expr.self = translate(value.gene_children[1])
  return expr

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["fn"] = translate_fn
    VM.gene_translators["fnx"] = translate_fnx
    VM.gene_translators["fnxx"] = translate_fnx
    VM.gene_translators["return"] = translate_return
    VM.gene_translators["$bind"] = translate_bind

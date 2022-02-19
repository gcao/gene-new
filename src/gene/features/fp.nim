import tables

import ../map_key
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

proc function_invoker*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var fn_scope = new_scope()
  fn_scope.set_parent(target.fn.parent_scope, target.fn.parent_scope_max)
  var new_frame = Frame(ns: target.fn.ns, scope: fn_scope)
  new_frame.parent = frame

  handle_args(self, frame, new_frame, target.fn.matcher, cast[ExArguments](expr))

  self.call_fn_skip_args(new_frame, target)

proc fn_arg_translator*(value: Value): Expr =
  return translate_arguments(value, function_invoker)

proc eval_fn(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  result = Value(
    kind: VkFunction,
    fn: cast[ExFn](expr).data,
  )
  result.fn.ns = frame.ns
  result.fn.parent_scope = frame.scope
  result.fn.parent_scope_max = frame.scope.max

proc to_function(node: Value): Function =
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
  result.translator = fn_arg_translator
  result.async = node.gene_props.get_or_default(ASYNC_KEY, false)

proc translate_fn(value: Value): Expr =
  var fn = to_function(value)
  var fn_expr = ExFn(
    evaluator: eval_fn,
    data: fn,
  )
  return translate_definition(value.gene_children[0], fn_expr)

proc translate_fnx(value: Value): Expr =
  var fn = to_function(value)
  ExFn(
    evaluator: eval_fn,
    data: fn,
  )

proc eval_return(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExReturn](expr)
  var r = Return(
    frame: frame,
  )
  if expr.data != nil:
    r.val = self.eval(frame, expr.data)
  else:
    r.val = Nil
  raise r

proc translate_return(value: Value): Expr =
  var expr = ExReturn()
  expr.evaluator = eval_return
  if value.gene_children.len > 0:
    expr.data = translate(value.gene_children[0])
  return expr

proc bound_function_invoker*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var bound_fn = target.bound_fn
  var fn = bound_fn.target.fn
  var fn_scope = new_scope()
  fn_scope.set_parent(fn.parent_scope, fn.parent_scope_max)
  var new_frame = Frame(ns: fn.ns, scope: fn_scope)
  new_frame.parent = frame
  new_frame.self = bound_fn.self

  handle_args(self, frame, new_frame, fn.matcher, cast[ExArguments](expr))

  self.call_fn_skip_args(new_frame, bound_fn.target)

proc bound_fn_arg_translator*(value: Value): Expr =
  return translate_arguments(value, bound_function_invoker)

proc eval_bind(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExBind](expr)
  var target = self.eval(frame, expr.target)
  var self = self.eval(frame, expr.self)
  var bound_fn = BoundFunction(
    translator: bound_fn_arg_translator,
    target: target,
    self: self,
    # args: args,
  )
  Value(kind: VkBoundFunction, bound_fn: bound_fn)

proc translate_bind(value: Value): Expr =
  var expr = ExBind()
  expr.evaluator = eval_bind
  expr.target = translate(value.gene_children[0])
  expr.self = translate(value.gene_children[1])
  return expr

proc init*() =
  GeneTranslators["fn"] = translate_fn
  GeneTranslators["fnx"] = translate_fnx
  GeneTranslators["fnxx"] = translate_fnx
  GeneTranslators["return"] = translate_return
  GeneTranslators["$bind"] = translate_bind

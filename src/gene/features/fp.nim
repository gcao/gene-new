import tables

import ../map_key
import ../types
import ../exprs
import ../translators
import ../interpreter

type
  ExFn* = ref object of Expr
    data*: Function

# proc process_args*(self: VirtualMachine, frame: Frame, matcher: RootMatcher, args: Value) =
#   var match_result = matcher.match(args)
#   case match_result.kind:
#   of MatchSuccess:
#     for field in match_result.fields:
#       if field.value_expr != nil:
#         frame.scope.def_member(field.name, self.eval(frame, field.value_expr))
#       else:
#         frame.scope.def_member(field.name, field.value)
#   of MatchMissingFields:
#     for field in match_result.missing:
#       not_allowed("Argument " & field.to_s & " is missing.")
#   else:
#     todo()

proc function_invoker*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var fn_scope = new_scope()
  fn_scope.set_parent(target.fn.parent_scope, target.fn.parent_scope_max)
  var new_frame = Frame(ns: target.fn.ns, scope: fn_scope)
  new_frame.parent = frame
  new_frame.self = target

  var expr = cast[ExArguments](expr)
  case target.fn.matching_hint.mode:
  of MhSimpleData:
    for _, v in expr.props.mpairs:
      discard self.eval(frame, v)
    for i, v in expr.data.mpairs:
      let field = target.fn.matcher.children[i]
      new_frame.scope.def_member(field.name, self.eval(frame, v))
  of MhNone:
    for _, v in expr.props.mpairs:
      discard self.eval(frame, v)
    for i, v in expr.data.mpairs:
      # var field = target.fn.matcher.children[i]
      discard self.eval(frame, v)
  else:
    todo()
    # self.process_args(new_frame, fn.matcher, self.eval(frame, args))

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
  # except CatchableError as e:
  #   if self.repl_on_error:
  #     result = repl_on_error(self, frame, e)
  #     discard
  #   else:
  #     raise

proc fn_arg_translator*(value: Value): Expr =
  var e = new_ex_arg()
  e.evaluator = function_invoker
  for k, v in value.gene_props:
    e.props[k] = translate(v)
  for v in value.gene_data:
    e.data.add(translate(v))
  return e

proc eval_fn(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  result = Value(
    kind: VkFunction,
    fn: cast[ExFn](expr).data,
  )
  result.fn.ns = frame.ns
  result.fn.parent_scope = frame.scope
  result.fn.parent_scope_max = frame.scope.max

proc to_function(node: Value): Function =
  var first = node.gene_data[0]
  var name: string
  if first.kind == VkSymbol:
    name = first.symbol
  elif first.kind == VkComplexSymbol:
    name = first.csymbol.rest[^1]

  var matcher = new_arg_matcher()
  matcher.parse(node.gene_data[1])

  var body: seq[Value] = @[]
  for i in 2..<node.gene_data.len:
    body.add node.gene_data[i]

  body = wrap_with_try(body)
  result = new_fn(name, matcher, body)
  result.translator = fn_arg_translator
  result.async = node.gene_props.get_or_default(ASYNC_KEY, false)

proc init*() =
  GeneTranslators["fn"] = proc(value: Value): Expr =
    var fn = to_function(value)
    var expr = new_ex_ns_def()
    expr.name = fn.name.to_key
    expr.value = ExFn(
      evaluator: eval_fn,
      data: fn,
    )
    return expr

import tables

import ../map_key
import ../types
import ../exprs
import ../translators
# import ../interpreter

type
  ExFn* = ref object of Expr
    data*: Function

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

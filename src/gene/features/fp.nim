import tables

import ../map_key
import ../types
import ../translators
import ../interpreter

proc to_function(node: Value): Function =
  var first = node.gene_data[0]
  var name: string
  if first.kind == VkSymbol:
    name = first.symbol
  elif first.kind == VkComplexSymbol:
    name = first.csymbol[^1]

  var matcher = new_arg_matcher()
  matcher.parse(node.gene_data[1])

  var body: seq[Value] = @[]
  for i in 2..<node.gene_data.len:
    body.add node.gene_data[i]

  body = wrap_with_try(body)
  result = new_fn(name, matcher, body)
  result.async = node.gene_props.get_or_default(ASYNC_KEY, false)

proc function_invoker(self: VirtualMachine, frame: Frame, target: Value, expr: Value): Value =
  var fn = target.fn
  var ns = fn.ns
  var fn_scope = new_scope()
  fn_scope.set_parent(fn.parent_scope, fn.parent_scope_max)
  var new_frame = Frame(ns: ns, scope: fn_scope)
  new_frame.parent = frame
  new_frame.self = target

  # self.process_args(new_frame, fn.matcher, new_frame.args)

  try:
    for e in fn.body:
      result = self.eval(new_frame, e)
  except Return as r:
    # return's frame is the same as new_frame(current function's frame)
    if r.frame == new_frame:
      result = r.val
    else:
      raise
  except CatchableError as e:
    if self.repl_on_error:
      # result = repl_on_error(self, frame, e)
      discard
    else:
      raise

proc init*() =
  GeneTranslators["fn"] = proc(v: Value): Value =
    var fn = to_function(v)
    result = Value(
      kind: VkExNsDef,
      ex_ns_def_name: fn.name.to_key,
      ex_ns_def_value: Value(
        kind: VkExFn,
        ex_fn: fn,
      ),
    )

  Evaluators[VkExFn] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    result = Value(
      kind: VkFunction,
      fn: expr.ex_fn,
    )

  Invokers[VkFunction] = function_invoker

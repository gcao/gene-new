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

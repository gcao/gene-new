import tables

import ../map_key
import ../types
import ../translators
import ../interpreter

type
  ExClass* = ref object of Expr
    name*: string
    body*: Expr

  ExNew* = ref object of Expr
    class*: Expr
    args*: Expr

  ExMethod* = ref object of Expr
    name*: string
    fn*: Function

proc eval_class(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var class = new_class(cast[ExClass](expr).name)
  class.ns.parent = frame.ns
  result = Value(kind: VkClass, class: class)
  frame.ns[cast[ExClass](expr).name] = result

  var new_frame = new_frame()
  new_frame.ns = class.ns
  new_frame.scope = new_scope()
  new_frame.self = result
  discard self.eval(new_frame, cast[ExClass](expr).body)

proc translate_class(value: Value): Expr =
  ExClass(
    evaluator: eval_class,
    name: value.gene_data[0].symbol,
    body: translate(value.gene_data[1..^1]),
  )

proc eval_new(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var instance = Instance()
  instance.class = self.eval(frame, cast[ExNew](expr).class).class
  result = Value(
    kind: VkInstance,
    instance: instance,
  )

proc translate_new(value: Value): Expr =
  ExNew(
    evaluator: eval_new,
    class: translate(value.gene_data[0]),
  )

# TODO: this is almost the same as to_function in fp.nim
proc to_function(node: Value): Function =
  var first = node.gene_data[0]
  var name = first.symbol

  var matcher = new_arg_matcher()
  matcher.parse(node.gene_data[1])

  var body: seq[Value] = @[]
  for i in 2..<node.gene_data.len:
    body.add node.gene_data[i]

  body = wrap_with_try(body)
  result = new_fn(name, matcher, body)
  result.async = node.gene_props.get_or_default(ASYNC_KEY, false)

proc eval_method(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  todo()

proc translate_method(value: Value): Expr =
  var fn = to_function(value)
  ExMethod(
    evaluator: eval_method,
    name: value.gene_data[0].symbol,
    fn: fn,
  )

proc init*() =
  GeneTranslators["class"] = translate_class
  GeneTranslators["new"] = translate_new
  GeneTranslators["method"] = translate_method

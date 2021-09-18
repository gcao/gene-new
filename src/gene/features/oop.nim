import tables

import ../map_key
import ../types
import ../exprs
import ../translators
import ../interpreter

let SELF_KEY*                 = add_key("self")
let METHOD_KEY*               = add_key("method")
let ARGS_KEY*                 = add_key("args")

type
  ExClass* = ref object of Expr
    container*: Expr
    name*: string
    body*: Expr

  ExNew* = ref object of Expr
    class*: Expr
    args*: Expr

  ExMethod* = ref object of Expr
    name*: string
    fn*: Function

  ExInvoke* = ref object of Expr
    self*: Expr
    meth*: MapKey
    args*: Expr

  ExInvokeDynamic* = ref object of Expr
    self*: Expr
    target*: Expr
    args*: Expr

proc eval_class(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExClass](expr)
  var class = new_class(e.name)
  class.ns.parent = frame.ns
  result = Value(kind: VkClass, class: class)
  var container = frame.ns
  if e.container != nil:
    container = self.eval(frame, e.container).ns
  container[e.name] = result

  var new_frame = new_frame()
  new_frame.ns = class.ns
  new_frame.scope = new_scope()
  new_frame.self = result
  discard self.eval(new_frame, e.body)

proc translate_class(value: Value): Expr =
  var e = ExClass(
    evaluator: eval_class,
    body: translate(value.gene_data[1..^1]),
  )
  var first = value.gene_data[0]
  case first.kind
  of VkSymbol:
    e.name = first.symbol
  of VkComplexSymbol:
    e.container = new_ex_names(first.csymbol)
    e.name = first.csymbol.rest[^1]
  else:
    todo()
  result = e

proc eval_new(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var instance = Instance()
  instance.class = self.eval(frame, cast[ExNew](expr).class).class
  result = Value(kind: VkInstance, instance: instance)
  var meth = instance.class.constructor
  if meth == nil:
    return

  var fn_scope = new_scope()
  var new_frame = Frame(ns: meth.fn.ns, scope: fn_scope)
  new_frame.parent = frame
  new_frame.self = result

  if meth.fn.body_compiled == nil:
    meth.fn.body_compiled = translate(meth.fn.body)

  try:
    discard self.eval(new_frame, meth.fn.body_compiled)
  except Return as r:
    # return's frame is the same as new_frame(current function's frame)
    if r.frame == new_frame:
      return
    else:
      raise

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

proc eval_method(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var m = Method(
    class: frame.self.class,
    name: cast[ExMethod](expr).name,
    fn: cast[ExMethod](expr).fn,
  )
  m.fn.ns = frame.ns
  if m.name == "new":
    frame.self.class.constructor = m
  else:
    frame.self.class.methods[m.name.to_key] = m
  Value(
    kind: VkMethod,
    `method`: m,
  )

proc translate_method(value: Value): Expr =
  var fn = to_function(value)
  ExMethod(
    evaluator: eval_method,
    name: value.gene_data[0].symbol,
    fn: fn,
  )

proc eval_invoke(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var instance: Value
  var e = cast[ExInvoke](expr).self
  if e == nil:
    instance = frame.self
  else:
    instance = self.eval(frame, e)
  var class = instance.instance.class
  var meth = class.methods[cast[ExInvoke](expr).meth]
  # var args = self.eval(frame, cast[ExInvoke](expr).args)

  var fn_scope = new_scope()
  var new_frame = Frame(ns: meth.fn.ns, scope: fn_scope)
  new_frame.parent = frame
  new_frame.self = instance

  if meth.fn.body_compiled == nil:
    meth.fn.body_compiled = translate(meth.fn.body)

  try:
    result = self.eval(new_frame, meth.fn.body_compiled)
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

proc translate_invoke(value: Value): Expr =
  var r = ExInvoke(
    evaluator: eval_invoke,
  )
  r.self = translate(value.gene_props.get_or_default(SELF_KEY, nil))
  r.meth = value.gene_props[METHOD_KEY].str.to_key
  # r.args = translate(value.gene_props[ARGS_KEY])
  result = r

proc eval_invoke_dynamic(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var instance: Value
  var e = cast[ExInvokeDynamic](expr).self
  if e == nil:
    instance = frame.self
  else:
    instance = self.eval(frame, e)
  var target = self.eval(frame, cast[ExInvokeDynamic](expr).target)
  var fn: Function
  case target.kind:
  of VkFunction:
    fn = target.fn
  else:
    todo()
  # var args = self.eval(frame, cast[ExInvoke](expr).args)

  var fn_scope = new_scope()
  var new_frame = Frame(ns: fn.ns, scope: fn_scope)
  new_frame.parent = frame
  new_frame.self = instance

  if fn.body_compiled == nil:
    fn.body_compiled = translate(fn.body)

  try:
    result = self.eval(new_frame, fn.body_compiled)
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

proc translate_invoke_dynamic(value: Value): Expr =
  var r = ExInvokeDynamic(
    evaluator: eval_invoke_dynamic,
  )
  r.self = translate(value.gene_props.get_or_default(SELF_KEY, nil))
  r.target = translate(value.gene_props[METHOD_KEY])
  # r.args = translate(value.gene_props[ARGS_KEY])
  result = r

proc init*() =
  GeneTranslators["class"] = translate_class
  GeneTranslators["new"] = translate_new
  GeneTranslators["method"] = translate_method
  GeneTranslators["$invoke_method"] = translate_invoke
  GeneTranslators["$invoke_dynamic"] = translate_invoke_dynamic

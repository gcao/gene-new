import tables

import ../map_key
import ../types
import ../exprs
import ../translators
import ../interpreter

let SELF_KEY*                 = add_key("self")
let METHOD_KEY*               = add_key("method")
# let ARGS_KEY*                 = add_key("args")

let LESS_THAN = new_gene_symbol("<")

type
  ExClass* = ref object of Expr
    parent*: Expr
    container*: Expr
    name*: string
    body*: Expr

  ExMixin* = ref object of Expr
    container*: Expr
    name*: string
    body*: Expr

  ExInclude* = ref object of Expr
    data*: seq[Expr]

  ExNew* = ref object of Expr
    class*: Expr
    args*: Expr

  ExMethod* = ref object of Expr
    name*: string
    fn*: Function

  ExMethodEq* = ref object of Expr
    name*: string
    value*: Expr

  ExInvoke* = ref object of Expr
    self*: Expr
    meth*: MapKey
    args*: Expr

  ExInvokeDynamic* = ref object of Expr
    self*: Expr
    target*: Expr
    args*: Expr

  ExSuper* = ref object of Expr
    args*: Expr

proc arg_translator*(value: Value): Expr =
  var e = new_ex_arg()
  for k, v in value.gene_props:
    e.props[k] = translate(v)
  for v in value.gene_data[1..^1]:
    e.data.add(translate(v))
  return e

proc eval_class(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExClass](expr)
  var class = new_class(e.name)
  if e.parent == nil:
    class.parent = ObjectClass.class
  else:
    class.parent = self.eval(frame, e.parent).class
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
  )
  var first = value.gene_data[0]
  case first.kind
  of VkSymbol:
    e.name = first.symbol
  of VkComplexSymbol:
    e.container = new_ex_names(first)
    e.name = first.csymbol[^1]
  else:
    todo()

  var body_start = 1
  if value.gene_data.len >= 3 and value.gene_data[1] == LESS_THAN:
    body_start = 3
    e.parent = translate(value.gene_data[2])
  e.body = translate(value.gene_data[body_start..^1])
  result = e

proc eval_mixin(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExMixin](expr)
  var m = new_mixin(e.name)
  m.ns.parent = frame.ns
  result = Value(kind: VkMixin, `mixin`: m)
  var container = frame.ns
  if e.container != nil:
    container = self.eval(frame, e.container).ns
  container[e.name] = result

  var new_frame = new_frame()
  new_frame.ns = m.ns
  new_frame.scope = new_scope()
  new_frame.self = result
  discard self.eval(new_frame, e.body)

proc translate_mixin(value: Value): Expr =
  var e = ExMixin(
    evaluator: eval_mixin,
  )
  var first = value.gene_data[0]
  case first.kind
  of VkSymbol:
    e.name = first.symbol
  of VkComplexSymbol:
    e.container = new_ex_names(first)
    e.name = first.csymbol[^1]
  else:
    todo()

  var body_start = 1
  e.body = translate(value.gene_data[body_start..^1])
  result = e

proc eval_include(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var x = frame.self
  for e in cast[ExInclude](expr).data.mitems:
    var m = self.eval(frame, e).mixin
    for _, meth in m.methods:
      var new_method = meth.clone
      case x.kind:
      of VkClass:
        new_method.class = x.class
        x.class.methods[new_method.name.to_key] = new_method
      of VkMixin:
        x.mixin.methods[new_method.name.to_key] = new_method
      else:
        not_allowed()

proc translate_include(value: Value): Expr =
  var e = ExInclude(
    evaluator: eval_include,
  )
  for item in value.gene_data:
    e.data.add(translate(item))

  result = e

proc eval_new(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var instance = Instance()
  instance.class = self.eval(frame, cast[ExNew](expr).class).class
  result = Value(kind: VkInstance, instance: instance)
  var meth = instance.class.constructor
  if meth == nil:
    return

  var fn_scope = new_scope()
  var new_frame = Frame(ns: meth.callable.fn.ns, scope: fn_scope)
  new_frame.parent = frame
  new_frame.self = result

  var args_expr = cast[ExNew](expr).args
  handle_args(self, frame, new_frame, meth.callable.fn, cast[ExArguments](args_expr))

  if meth.callable.fn.body_compiled == nil:
    meth.callable.fn.body_compiled = translate(meth.callable.fn.body)

  try:
    discard self.eval(new_frame, meth.callable.fn.body_compiled)
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
    args: arg_translator(value),
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

proc assign_method(frame: Frame, m: Method) =
  case frame.self.kind:
  of VkClass:
    m.class = frame.self.class
    if m.name == "new":
      frame.self.class.constructor = m
    else:
      frame.self.class.methods[m.name.to_key] = m
  of VkMixin:
    if m.name == "new":
      not_allowed()
    else:
      frame.self.mixin.methods[m.name.to_key] = m
  else:
    not_allowed()

proc eval_method(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var m = Method(
    name: cast[ExMethod](expr).name,
    callable: Value(kind: VkFunction, fn: cast[ExMethod](expr).fn),
  )
  m.callable.fn.ns = frame.ns
  assign_method(frame, m)

  Value(
    kind: VkMethod,
    `method`: m,
  )

proc eval_method_eq*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var m = Method(
    name: cast[ExMethodEq](expr).name,
    callable: self.eval(frame, cast[ExMethodEq](expr).value),
  )
  assign_method(frame, m)

  Value(
    kind: VkMethod,
    `method`: m,
  )

proc translate_method(value: Value): Expr =
  if value.gene_data.len >= 3 and value.gene_data[1] == Equal:
    return ExMethodEq(
      evaluator: eval_method_eq,
      name: value.gene_data[0].symbol,
      value: translate(value.gene_data[2])
    )

  var fn = to_function(value)
  ExMethod(
    evaluator: eval_method,
    name: value.gene_data[0].symbol,
    fn: fn,
  )

proc eval_invoke*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var instance: Value
  var e = cast[ExInvoke](expr).self
  if e == nil:
    instance = frame.self
  else:
    instance = self.eval(frame, e)
  var class = instance.get_class
  var meth = class.get_method(cast[ExInvoke](expr).meth)

  case meth.callable.kind:
  of VkNativeMethod:
    var args_expr = cast[ExArguments](cast[ExInvoke](expr).args)
    var args = new_gene_gene()
    for k, v in args_expr.props.mpairs:
      args.gene_props[k] = self.eval(frame, v)
    for _, v in args_expr.data.mpairs:
      args.gene_data.add self.eval(frame, v)
    result = meth.callable.native_method(instance, args)

  of VkFunction:
    var fn_scope = new_scope()
    var new_frame = Frame(ns: meth.callable.fn.ns, scope: fn_scope)
    new_frame.parent = frame
    new_frame.self = instance
    new_frame.extra = FrameExtra(kind: FrMethod, `method`: meth)

    var args_expr = cast[ExInvoke](expr).args
    handle_args(self, frame, new_frame, meth.callable.fn, cast[ExArguments](args_expr))

    if meth.callable.fn.body_compiled == nil:
      meth.callable.fn.body_compiled = translate(meth.callable.fn.body)

    try:
      result = self.eval(new_frame, meth.callable.fn.body_compiled)
    except Return as r:
      # return's frame is the same as new_frame(current function's frame)
      if r.frame == new_frame:
        result = r.val
      else:
        raise
    except CatchableError as e:
      if self.repl_on_error:
        result = repl_on_error(self, frame, e)
        discard
      else:
        raise
  else:
    todo()

proc translate_invoke(value: Value): Expr =
  var r = ExInvoke(
    evaluator: eval_invoke,
  )
  r.self = translate(value.gene_props.get_or_default(SELF_KEY, nil))
  r.meth = value.gene_props[METHOD_KEY].str.to_key

  var args = new_ex_arg()
  for v in value.gene_data:
    args.data.add(translate(v))
  r.args = args

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
  except CatchableError as e:
    if self.repl_on_error:
      result = repl_on_error(self, frame, e)
      discard
    else:
      raise

proc translate_invoke_dynamic(value: Value): Expr =
  var r = ExInvokeDynamic(
    evaluator: eval_invoke_dynamic,
  )
  r.self = translate(value.gene_props.get_or_default(SELF_KEY, nil))
  r.target = translate(value.gene_props[METHOD_KEY])
  # r.args = translate(value.gene_props[ARGS_KEY])
  result = r

proc eval_super(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var instance = frame.self
  var m = frame.extra.method
  var meth = m.class.get_super_method(m.name.to_key)

  var fn_scope = new_scope()
  var new_frame = Frame(ns: meth.callable.fn.ns, scope: fn_scope)
  new_frame.parent = frame
  new_frame.self = instance

  var args_expr = cast[ExSuper](expr).args
  handle_args(self, frame, new_frame, meth.callable.fn, cast[ExArguments](args_expr))

  if meth.callable.fn.body_compiled == nil:
    meth.callable.fn.body_compiled = translate(meth.callable.fn.body)

  try:
    result = self.eval(new_frame, meth.callable.fn.body_compiled)
  except Return as r:
    # return's frame is the same as new_frame(current function's frame)
    if r.frame == new_frame:
      result = r.val
    else:
      raise
  except CatchableError as e:
    if self.repl_on_error:
      result = repl_on_error(self, frame, e)
      discard
    else:
      raise

proc translate_super(value: Value): Expr =
  var r = ExSuper(
    evaluator: eval_super,
  )
  var args = new_ex_arg()
  for v in value.gene_data:
    args.data.add(translate(v))
  r.args = args
  result = r

proc def_native_method*(self: Value, name: string, m: NativeMethod) =
  self.class.methods[name.to_key] = Method(
    class: self.class,
    name: name,
    callable: Value(kind: VkNativeMethod, native_method: m),
  )

proc init*() =
  GeneTranslators["class"] = translate_class
  GeneTranslators["mixin"] = translate_mixin
  GeneTranslators["include"] = translate_include
  GeneTranslators["new"] = translate_new
  GeneTranslators["method"] = translate_method
  GeneTranslators["$invoke_method"] = translate_invoke
  GeneTranslators["$invoke_dynamic"] = translate_invoke_dynamic
  GeneTranslators["super"] = translate_super

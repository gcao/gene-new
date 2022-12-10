import tables

import ../map_key
import ../types
import ../interpreter_base
import ./symbol

let LESS_THAN = new_gene_symbol("<")

type
  ExClass* = ref object of Expr
    parent*: Expr
    container*: Expr
    name*: string
    body*: Expr

  ExObject* = ref object of Expr
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

  # Either fn or value is given
  ExConstructor* = ref object of Expr
    fn*: Function
    value*: Expr

  ExInvokeDynamic* = ref object of Expr
    self*: Expr
    target*: Expr
    args*: Expr

  ExSuper* = ref object of Expr
    args*: Expr

  # ExGetProp* = ref object of Expr
  #   self*: Expr
  #   name*: Expr

  # ExSetProp* = ref object of Expr
  #   self*: Expr
  #   name*: Expr
  #   value*: Expr

  # ExMethodMissing* = ref object of Expr
  #   fn: Function

proc eval_class(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExClass](expr)
  var class = new_class(e.name)
  result = Value(kind: VkClass, class: class)
  if e.parent == nil:
    class.parent = VM.object_class.class
  else:
    var parent = self.eval(frame, e.parent)
    class.parent = parent.class
    if not parent.class.on_extended.is_nil:
      var f = new_frame()
      f.self = parent
      var args = new_gene_gene()
      args.gene_children.add(result)
      discard VM.call(f, parent, parent.class.on_extended, args)
  class.ns.parent = frame.ns
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
  var first = value.gene_children[0]
  case first.kind
  of VkSymbol:
    e.name = first.str
  of VkComplexSymbol:
    e.container = translate(first.csymbol[0..^2])
    e.name = first.csymbol[^1]
  else:
    todo()

  var body_start = 1
  if value.gene_children.len >= 3 and value.gene_children[1] == LESS_THAN:
    body_start = 3
    e.parent = translate(value.gene_children[2])
  e.body = translate(value.gene_children[body_start..^1])
  return translate_definition(value.gene_children[0], e)

proc eval_object(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExObject](expr)
  var class = new_class(e.name)
  var class_val = Value(kind: VkClass, class: class)
  result = new_gene_instance(class, Table[MapKey, Value]())
  if e.parent == nil:
    class.parent = VM.object_class.class
  else:
    var parent = self.eval(frame, e.parent)
    class.parent = parent.class
    if not parent.class.on_extended.is_nil:
      var f = new_frame()
      f.self = parent
      var args = new_gene_gene()
      args.gene_children.add(class_val)
      discard VM.call(f, parent, parent.class.on_extended, args)
  class.ns.parent = frame.ns
  # TODO
  # var container = frame.ns
  # if e.container != nil:
  #   container = self.eval(frame, e.container).ns
  # container[e.name] = result

  var new_frame = new_frame()
  new_frame.ns = class.ns
  new_frame.scope = new_scope()
  new_frame.self = class_val
  discard self.eval(new_frame, e.body)

  var init = class.get_method(INIT_KEY)
  if init != nil:
    discard self.invoke(frame, result, INIT_KEY, Value(kind: VkNil))

proc translate_object(value: Value): Expr =
  var e = ExObject(
    evaluator: eval_object,
  )
  var first = value.gene_children[0]
  case first.kind
  of VkSymbol:
    e.name = first.str
  of VkComplexSymbol:
    e.container = translate(first.csymbol[0..^2])
    e.name = first.csymbol[^1]
  else:
    todo()

  var body_start = 1
  if value.gene_children.len >= 3 and value.gene_children[1].is_symbol("<"):
    body_start = 3
    e.parent = translate(value.gene_children[2])
  e.body = translate(value.gene_children[body_start..^1])
  return translate_definition(value.gene_children[0], e)

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
  var first = value.gene_children[0]
  case first.kind
  of VkSymbol:
    e.name = first.str
  of VkComplexSymbol:
    e.container = translate(first.csymbol[0..^2])
    e.name = first.csymbol[^1]
  else:
    todo()

  var body_start = 1
  e.body = translate(value.gene_children[body_start..^1])
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
  for item in value.gene_children:
    e.data.add(translate(item))

  result = e

proc eval_new(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExNew](expr)
  var class = self.eval(frame, expr.class).class
  var ctor = class.get_constructor()
  if ctor == nil:
    result = Value(
      kind: VkInstance,
      instance_class: class,
    )
    # TODO: should "init" be called for instances created by custom constructors?
    var init = class.get_method(INIT_KEY)
    if init != nil:
      discard self.invoke(frame, result, INIT_KEY, expr.args)
  else:
    case ctor.kind:
    of VkNativeFn, VkNativeFn2:
      var args = self.eval_args(frame, nil, expr.args)
      if ctor.kind == VkNativeFn:
        result = ctor.native_fn(args)
      else:
        result = ctor.native_fn2(args)
    of VkFunction:
      result = Value(
        kind: VkInstance,
        instance_class: class,
      )
      var fn_scope = new_scope()
      var new_frame = Frame(ns: ctor.fn.ns, scope: fn_scope)
      new_frame.parent = frame
      new_frame.self = result

      var args_expr = cast[ExNew](expr).args
      handle_args(self, frame, new_frame, ctor.fn.matcher, cast[ExArguments](args_expr))

      if ctor.fn.body_compiled == nil:
        ctor.fn.body_compiled = translate(ctor.fn.body)

      try:
        discard self.eval(new_frame, ctor.fn.body_compiled)
      except Return as r:
        # return's frame is the same as new_frame(current function's frame)
        if r.frame == new_frame:
          return
        else:
          raise
    else:
      todo("eval_new " & $ctor.kind)

proc translate_new(value: Value): Expr =
  var r = ExNew(
    evaluator: eval_new,
    class: translate(value.gene_children[0]),
    args: new_ex_arg(),
  )
  for k, v in value.gene_props:
    cast[ExArguments](r.args).props[k] = translate(v)
  for v in value.gene_children[1..^1]:
    cast[ExArguments](r.args).children.add(translate(v))
  return r

# TODO: this is almost the same as to_function in fp.nim
proc to_function(node: Value): Function =
  var first = node.gene_children[0]
  var name = first.str

  var matcher = new_arg_matcher()
  matcher.parse(node.gene_children[1])

  var body: seq[Value] = @[]
  for i in 2..<node.gene_children.len:
    body.add node.gene_children[i]

  body = wrap_with_try(body)
  result = new_fn(name, matcher, body)
  result.async = node.gene_props.get_or_default(ASYNC_KEY, false)

proc to_constructor(node: Value): Function =
  var name = "new"

  var matcher = new_arg_matcher()
  matcher.parse(node.gene_children[0])

  var body: seq[Value] = @[]
  for i in 1..<node.gene_children.len:
    body.add node.gene_children[i]

  body = wrap_with_try(body)
  result = new_fn(name, matcher, body)

proc assign_method(frame: Frame, m: Method) =
  case frame.self.kind:
  of VkClass:
    m.class = frame.self.class
    frame.self.class.methods[m.name.to_key] = m
  of VkMixin:
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
  if value.gene_children.len >= 3 and value.gene_children[1].is_symbol("="):
    return ExMethodEq(
      evaluator: eval_method_eq,
      name: value.gene_children[0].str,
      value: translate(value.gene_children[2])
    )

  var fn = to_function(value)
  ExMethod(
    evaluator: eval_method,
    name: value.gene_children[0].str,
    fn: fn,
  )

proc eval_constructor*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExConstructor](expr)
  var class = frame.self.class
  if expr.fn != nil:
    class.constructor = Value(kind: VkFunction, fn: expr.fn)
  else:
    class.constructor = self.eval(frame, expr.value)

proc translate_constructor(value: Value): Expr =
  var r = ExConstructor(
    evaluator: eval_constructor,
  )
  if value.gene_type.str == "$def_constructor":
    r.fn = value.to_constructor()
  else:
    r.value = translate(value.gene_children[0])
  result = r

proc eval_invoke_dynamic(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExInvokeDynamic](expr)
  var instance: Value
  var e = expr.self
  if e == nil:
    instance = frame.self
  else:
    instance = self.eval(frame, e)
  var target = self.eval(frame, expr.target)
  case target.kind:
  of VkString:
    return self.invoke(frame, instance, target.str.to_key, expr.args)
  of VkSymbol:
    return self.invoke(frame, instance, target.str.to_key, expr.args)
  of VkFunction:
    var fn = target.fn
    var fn_scope = new_scope()
    var new_frame = Frame(ns: fn.ns, scope: fn_scope)
    new_frame.parent = frame
    new_frame.self = instance

    if fn.body_compiled == nil:
      fn.body_compiled = translate(fn.body)

    try:
      handle_args(self, frame, new_frame, fn.matcher, cast[ExArguments](expr.args))
      result = self.eval(new_frame, fn.body_compiled)
    except Return as r:
      # return's frame is the same as new_frame(current function's frame)
      if r.frame == new_frame:
        result = r.val
      else:
        raise
    except system.Exception as e:
      if self.repl_on_error:
        result = repl_on_error(self, frame, e)
        discard
      else:
        raise

  else:
    todo("eval_invoke_dynamic " & $target.kind)

proc translate_invoke_dynamic(value: Value): Expr =
  var r = ExInvokeDynamic(
    evaluator: eval_invoke_dynamic,
  )
  r.self = translate(value.gene_props.get_or_default(SELF_KEY, nil))
  r.target = translate(value.gene_props[METHOD_KEY])

  var args = new_ex_arg()
  for k, v in value.gene_props:
    args.props[k] = translate(v)
  for v in value.gene_children:
    args.children.add(translate(v))
  r.args = args

  result = r

proc eval_super(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExSuper](expr)
  var instance = frame.self
  var m = frame.extra.method
  var meth = m.class.get_super_method(m.name.to_key)

  var fn_scope = new_scope()
  var new_frame = Frame(ns: meth.callable.fn.ns, scope: fn_scope)
  new_frame.parent = frame
  new_frame.self = instance

  handle_args(self, frame, new_frame, meth.callable.fn.matcher, cast[ExArguments](expr.args))

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
  except system.Exception as e:
    if self.repl_on_error:
      result = repl_on_error(self, frame, e)
      discard
    else:
      raise

proc translate_super(value: Value): Expr =
  return ExSuper(
    evaluator: eval_super,
    args: new_ex_arg(value),
  )

# proc eval_get_prop(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
#   var expr = cast[ExGetProp](expr)
#   var name = self.eval(frame, expr.name)
#   var obj =
#     if expr.self == nil:
#       frame.self
#     else:
#       self.eval(frame, expr.self)
#   case obj.kind:
#   of VkInstance:
#     return obj.instance_props[name.str.to_key]
#   else:
#     todo("eval_get_prop " & $obj & " " & name.to_s)

# proc translate_get_prop(value: Value): Expr =
#   if value.gene_children.len == 1:
#     return ExGetProp(
#       evaluator: eval_get_prop,
#       name: translate(value.gene_children[0]),
#     )
#   else:
#     return ExGetProp(
#       evaluator: eval_get_prop,
#       self: translate(value.gene_children[0]),
#       name: translate(value.gene_children[1]),
#     )

# proc eval_set_prop(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
#   var expr = cast[ExSetProp](expr)
#   var name = self.eval(frame, expr.name)
#   result = self.eval(frame, expr.value)
#   var obj =
#     if expr.self == nil:
#       frame.self
#     else:
#       self.eval(frame, expr.self)
#   case obj.kind:
#   of VkInstance:
#     obj.instance_props[name.str.to_key] = result
#   else:
#     todo("eval_set_prop " & $obj & " " & name.to_s)

# proc translate_set_prop(value: Value): Expr =
#   if value.gene_children.len == 2:
#     return ExSetProp(
#       evaluator: eval_set_prop,
#       name: translate(value.gene_children[0]),
#       value: translate(value.gene_children[1]),
#     )
#   else:
#     return ExSetProp(
#       evaluator: eval_set_prop,
#       self: translate(value.gene_children[0]),
#       name: translate(value.gene_children[1]),
#       value: translate(value.gene_children[2]),
#     )

# proc eval_method_missing(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
#   result = Value(
#     kind: VkFunction,
#     fn: cast[ExMethodMissing](expr).fn,
#   )
#   result.fn.ns = frame.ns
#   result.fn.parent_scope = frame.scope
#   result.fn.parent_scope_max = frame.scope.max
#   frame.self.class.method_missing = result

# proc translate_method_missing(value: Value): Expr =
#   var name = "method_missing"
#   var matcher = new_arg_matcher()
#   matcher.parse(value.gene_children[0])

#   var body: seq[Value] = @[]
#   for i in 1..<value.gene_children.len:
#     body.add value.gene_children[i]

#   body = wrap_with_try(body)
#   var fn = new_fn(name, matcher, body)

#   ExMethodMissing(
#     evaluator: eval_method_missing,
#     fn: fn,
#   )

proc init*() =
  GeneTranslators["class"] = translate_class
  GeneTranslators["$def_constructor"] = translate_constructor
  GeneTranslators["$set_constructor"] = translate_constructor
  GeneTranslators["mixin"] = translate_mixin
  GeneTranslators["include"] = translate_include
  GeneTranslators["new"] = translate_new
  GeneTranslators["method"] = translate_method
  GeneTranslators["super"] = translate_super
  GeneTranslators["$invoke_method"] = translate_invoke
  GeneTranslators["$invoke_dynamic"] = translate_invoke_dynamic
  # GeneTranslators["$get_prop"] = translate_get_prop
  # GeneTranslators["$set_prop"] = translate_set_prop
  # GeneTranslators["method_missing"] = translate_method_missing
  GeneTranslators["$object"] = translate_object

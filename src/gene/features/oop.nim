import tables

import ../types
import ../interpreter_base
import ./symbol

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
    args*: Value

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
    args*: Value

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

proc eval_class(frame: Frame, expr: var Expr): Value =
  var e = cast[ExClass](expr)
  var class = new_class(e.name)
  result = Value(kind: VkClass, class: class)
  if e.parent == nil:
    class.parent = VM.object_class.class
  else:
    var parent = eval(frame, e.parent)
    class.parent = parent.class
    if not parent.class.on_extended.is_nil:
      var f = new_frame()
      f.self = parent
      var args = new_gene_gene()
      args.gene_children.add(result)
      discard call(f, parent, parent.class.on_extended, args)
  class.ns.parent = frame.ns
  var container = frame.ns
  if e.container != nil:
    container = eval(frame, e.container).ns
  container[e.name] = result

  var new_frame = new_frame()
  new_frame.ns = class.ns
  new_frame.scope = new_scope()
  new_frame.self = result
  discard eval(new_frame, e.body)

proc translate_class(value: Value): Expr {.gcsafe.} =
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
  if value.gene_children.len >= 3 and value.gene_children[1].is_symbol("<"):
    body_start = 3
    e.parent = translate(value.gene_children[2])
  e.body = translate(value.gene_children[body_start..^1])
  return translate_definition(value.gene_children[0], e)

proc eval_object(frame: Frame, expr: var Expr): Value =
  var e = cast[ExObject](expr)
  var class = new_class(e.name)
  var class_val = Value(kind: VkClass, class: class)
  result = new_gene_instance(class, Table[string, Value]())
  if e.parent == nil:
    class.parent = VM.object_class.class
  else:
    var parent = eval(frame, e.parent)
    class.parent = parent.class
    if not parent.class.on_extended.is_nil:
      var f = new_frame()
      f.self = parent
      var args = new_gene_gene()
      args.gene_children.add(class_val)
      discard call(f, parent, parent.class.on_extended, args)
  class.ns.parent = frame.ns
  # TODO
  # var container = frame.ns
  # if e.container != nil:
  #   container = eval(frame, e.container).ns
  # container[e.name] = result

  var new_frame = new_frame()
  new_frame.ns = class.ns
  new_frame.scope = new_scope()
  new_frame.self = class_val
  discard eval(new_frame, e.body)

  let ctor = class.get_constructor()
  if ctor.is_nil:
    return

  case ctor.kind:
  of VkNativeFn, VkNativeFn2:
    var args = Value(kind: VkNil)
    if ctor.kind == VkNativeFn:
      result = ctor.native_fn(frame, args)
    else:
      result = ctor.native_fn2(frame, args)
  of VkFunction:
    result = Value(
      kind: VkInstance,
      instance_class: class,
    )
    var fn_scope = new_scope()
    var new_frame = Frame(ns: ctor.fn.ns, scope: fn_scope)
    new_frame.parent = frame
    new_frame.self = result

    var args = new_ex_arg()
    handle_args(frame, new_frame, ctor.fn.matcher, args)

    if ctor.fn.body_compiled == nil:
      ctor.fn.body_compiled = translate(ctor.fn.body)

    try:
      discard eval(new_frame, ctor.fn.body_compiled)
    except Return as r:
      # return's frame is the same as new_frame(current function's frame)
      if r.frame == new_frame:
        return
      else:
        raise
  else:
    todo("eval_object " & $ctor.kind)

proc translate_object(value: Value): Expr {.gcsafe.} =
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

proc eval_mixin(frame: Frame, expr: var Expr): Value =
  var e = cast[ExMixin](expr)
  var m = new_mixin(e.name)
  m.ns.parent = frame.ns
  result = Value(kind: VkMixin, `mixin`: m)
  var container = frame.ns
  if e.container != nil:
    container = eval(frame, e.container).ns
  container[e.name] = result

  var new_frame = new_frame()
  new_frame.ns = m.ns
  new_frame.scope = new_scope()
  new_frame.self = result
  discard eval(new_frame, e.body)

proc translate_mixin(value: Value): Expr {.gcsafe.} =
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

proc eval_include(frame: Frame, expr: var Expr): Value =
  var x = frame.self
  for e in cast[ExInclude](expr).data.mitems:
    var m = eval(frame, e).mixin
    for _, meth in m.methods:
      var new_method = meth.clone
      case x.kind:
      of VkClass:
        new_method.class = x.class
        x.class.methods[new_method.name] = new_method
      of VkMixin:
        x.mixin.methods[new_method.name] = new_method
      else:
        not_allowed()

proc translate_include(value: Value): Expr {.gcsafe.} =
  var e = ExInclude(
    evaluator: eval_include,
  )
  for item in value.gene_children:
    e.data.add(translate(item))

  result = e

proc eval_new(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExNew](expr)
  var class = eval(frame, expr.class).class
  var ctor = class.get_constructor()
  if ctor == nil:
    result = Value(
      kind: VkInstance,
      instance_class: class,
    )
  else:
    case ctor.kind:
    of VkNativeFn, VkNativeFn2:
      var args_expr: Expr = new_ex_arg(expr.args)
      var args = eval_args(frame, args_expr)
      if ctor.kind == VkNativeFn:
        result = ctor.native_fn(frame, args)
      else:
        result = ctor.native_fn2(frame, args)
    of VkFunction:
      result = Value(
        kind: VkInstance,
        instance_class: class,
      )
      var fn_scope = new_scope()
      var new_frame = Frame(ns: ctor.fn.ns, scope: fn_scope)
      new_frame.parent = frame
      new_frame.self = result

      var args = new_ex_arg(expr.args)
      handle_args(frame, new_frame, ctor.fn.matcher, args)

      if ctor.fn.body_compiled == nil:
        ctor.fn.body_compiled = translate(ctor.fn.body)

      try:
        discard eval(new_frame, ctor.fn.body_compiled)
      except Return as r:
        # return's frame is the same as new_frame(current function's frame)
        if r.frame == new_frame:
          return
        else:
          raise
    else:
      todo("eval_new " & $ctor.kind)

proc translate_new(value: Value): Expr {.gcsafe.} =
  var r = ExNew(
    evaluator: eval_new,
    class: translate(value.gene_children[0]),
    args: new_gene_gene(),
  )
  for k, v in value.gene_props:
    r.args.gene_props[k] = v
  for v in value.gene_children[1..^1]:
    r.args.gene_children.add(v)
  return r

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
    frame.self.class.methods[m.name] = m
  of VkMixin:
    frame.self.mixin.methods[m.name] = m
  else:
    not_allowed()

proc eval_method_eq*(frame: Frame, expr: var Expr): Value =
  var m = Method(
    name: cast[ExMethodEq](expr).name,
    callable: eval(frame, cast[ExMethodEq](expr).value),
  )
  assign_method(frame, m)

  Value(
    kind: VkMethod,
    `method`: m,
  )

proc eval_constructor*(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExConstructor](expr)
  var class = frame.self.class
  if expr.fn != nil:
    class.constructor = Value(kind: VkFunction, fn: expr.fn)
  else:
    class.constructor = eval(frame, expr.value)

proc translate_constructor(value: Value): Expr {.gcsafe.} =
  var r = ExConstructor(
    evaluator: eval_constructor,
  )
  if value.gene_type.str == "$def_constructor":
    r.fn = value.to_constructor()
  else:
    r.value = translate(value.gene_children[0])
  result = r

proc eval_invoke_dynamic(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExInvokeDynamic](expr)
  var instance: Value
  var e = expr.self
  if e == nil:
    instance = frame.self
  else:
    instance = eval(frame, e)
  var target = eval(frame, expr.target)
  case target.kind:
  of VkString:
    return invoke(frame, instance, target.str, expr.args)
  of VkSymbol:
    return invoke(frame, instance, target.str, expr.args)
  of VkFunction:
    var fn = target.fn
    var fn_scope = new_scope()
    var new_frame = Frame(ns: fn.ns, scope: fn_scope)
    new_frame.parent = frame
    new_frame.self = instance

    if fn.body_compiled == nil:
      fn.body_compiled = translate(fn.body)

    try:
      var args = new_ex_arg(expr.args)
      handle_args(frame, new_frame, fn.matcher, args)
      result = eval(new_frame, fn.body_compiled)
    except Return as r:
      # return's frame is the same as new_frame(current function's frame)
      if r.frame == new_frame:
        result = r.val
      else:
        raise
    except system.Exception as e:
      if VM.repl_on_error:
        result = repl_on_error(frame, e)
        discard
      else:
        raise

  else:
    todo("eval_invoke_dynamic " & $target.kind)

proc translate_invoke_dynamic(value: Value): Expr {.gcsafe.} =
  var r = ExInvokeDynamic(
    evaluator: eval_invoke_dynamic,
  )
  r.self = translate(value.gene_props.get_or_default("self", nil))
  r.target = translate(value.gene_props["method"])
  r.args = value

  result = r

proc eval_super(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExSuper](expr)
  var instance = frame.self
  var m = frame.callable.method
  var meth = m.class.get_super_method(m.name)

  var fn_scope = new_scope()
  var new_frame = Frame(ns: meth.callable.fn.ns, scope: fn_scope)
  new_frame.parent = frame
  new_frame.self = instance

  handle_args(frame, new_frame, meth.callable.fn.matcher, cast[ExArguments](expr.args))

  if meth.callable.fn.body_compiled == nil:
    meth.callable.fn.body_compiled = translate(meth.callable.fn.body)

  try:
    result = eval(new_frame, meth.callable.fn.body_compiled)
  except Return as r:
    # return's frame is the same as new_frame(current function's frame)
    if r.frame == new_frame:
      result = r.val
    else:
      raise
  except system.Exception as e:
    if VM.repl_on_error:
      result = repl_on_error(frame, e)
      discard
    else:
      raise

proc translate_super(value: Value): Expr {.gcsafe.} =
  return ExSuper(
    evaluator: eval_super,
    args: new_ex_arg(value),
  )

# proc eval_get_prop(frame: Frame, expr: var Expr): Value =
#   var expr = cast[ExGetProp](expr)
#   var name = eval(frame, expr.name)
#   var obj =
#     if expr.self == nil:
#       frame.self
#     else:
#       eval(frame, expr.self)
#   case obj.kind:
#   of VkInstance:
#     return obj.instance_props[name.str]
#   else:
#     todo("eval_get_prop " & $obj & " " & name.to_s)

# proc translate_get_prop(value: Value): Expr {.gcsafe.} =
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

# proc eval_set_prop(frame: Frame, expr: var Expr): Value =
#   var expr = cast[ExSetProp](expr)
#   var name = eval(frame, expr.name)
#   result = eval(frame, expr.value)
#   var obj =
#     if expr.self == nil:
#       frame.self
#     else:
#       eval(frame, expr.self)
#   case obj.kind:
#   of VkInstance:
#     obj.instance_props[name.str] = result
#   else:
#     todo("eval_set_prop " & $obj & " " & name.to_s)

# proc translate_set_prop(value: Value): Expr {.gcsafe.} =
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

# proc eval_method_missing(frame: Frame, expr: var Expr): Value =
#   result = Value(
#     kind: VkFunction,
#     fn: cast[ExMethodMissing](expr).fn,
#   )
#   result.fn.ns = frame.ns
#   result.fn.parent_scope = frame.scope
#   result.fn.parent_scope_max = frame.scope.max
#   frame.self.class.method_missing = result

# proc translate_method_missing(value: Value): Expr {.gcsafe.} =
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
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["class"] = translate_class
    VM.gene_translators["$def_constructor"] = translate_constructor
    VM.gene_translators["$set_constructor"] = translate_constructor
    VM.gene_translators["mixin"] = translate_mixin
    VM.gene_translators["include"] = translate_include
    VM.gene_translators["new"] = translate_new
    VM.gene_translators["super"] = translate_super
    VM.gene_translators["$invoke_method"] = translate_invoke
    VM.gene_translators["$invoke_dynamic"] = translate_invoke_dynamic
    # VM.gene_translators["$get_prop"] = translate_get_prop
    # VM.gene_translators["$set_prop"] = translate_set_prop
    # VM.gene_translators["method_missing"] = translate_method_missing
    VM.gene_translators["$object"] = translate_object

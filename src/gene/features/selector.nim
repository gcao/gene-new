import strutils, tables

import ../types
import ../interpreter_base

type
  NoResult* = ref object of types.Exception

  ExSelector* = ref object of Expr
    data*: Expr

  ExSelector2* = ref object of Expr
    parallel_mode*: bool
    data*: seq[Expr]

  ExInvokeSelector* = ref object of Expr
    name*: Expr
    args*: Expr

  ExSelectorInvoker* = ref object of Expr
    data*: Expr

  ExSelectorInvoker2* = ref object of Expr
    selector*: Expr
    target*: Expr

proc search*(self: Selector, target: Value, r: SelectorResult) {.gcsafe.}

proc search_first(self: SelectorMatcher, target: Value): Value =
  case self.kind:
  of SmByIndex:
    case target.kind:
    of VkVector:
      if self.index >= target.vec.len:
        raise NoResult.new
      else:
        if self.index < 0:
          return target.vec[self.index + target.vec.len]
        else:
          return target.vec[self.index]
    of VkGene:
      if self.index >= target.gene_children.len:
        raise NoResult.new
      else:
        if self.index < 0:
          return target.gene_children[self.index + target.gene_children.len]
        else:
          return target.gene_children[self.index]
    else:
      todo("search_first " & $target.kind)
  of SmByName:
    case target.kind:
    of VkMap:
      if target.map.has_key(self.name):
        return target.map[self.name]
      else:
        raise NoResult.new
    of VkGene:
      if target.gene_props.has_key(self.name):
        return target.gene_props[self.name]
      else:
        raise NoResult.new
    of VkInstance:
      return target.instance_props.get_or_default(self.name, Value(kind: VkNil))
    of VkNamespace:
      return target.ns[self.name]
    of VkClass:
      return target.class.ns[self.name]
    of VkMixin:
      return target.mixin.ns[self.name]
    else:
      todo($target.kind)
  of SmByType:
    case target.kind:
    of VkVector:
      for item in target.vec:
        if item.kind == VkGene and item.gene_type == self.by_type:
          return item
    else:
      todo($target.kind)
  of SmInvoke:
    var args = new_gene_gene(Value(kind: VkNil))
    return invoke(new_frame(), target, self.invoke_name, args)
  else:
    todo()

proc add_self_and_descendants(self: var seq[Value], v: Value) =
  self.add(v)
  case v.kind:
  of VkVector:
    for child in v.vec:
      self.add_self_and_descendants(child)
  of VkGene:
    for child in v.gene_children:
      self.add_self_and_descendants(child)
  else:
    discard

proc search(self: SelectorMatcher, target: Value): seq[Value] =
  case self.kind:
  of SmByIndex:
    case target.kind:
    of VkVector:
      result.add(target.vec[self.index])
    of VkGene:
      result.add(target.gene_children[self.index])
    else:
      todo("search SmByIndex " & $target.kind)
  of SmByIndexRange:
    case target.kind:
    of VkVector:
      var len = target.vec.len
      var i = cast[int](self.range.start.int)
      if i < 0:
        i += len
      var `end` = cast[int](self.range.end.int)
      if `end` < 0:
        `end` += len
      while i < len and i <= `end`:
        if i >= 0:
          result.add(target.vec[i])
        i += 1
    of VkGene:
      var len = target.gene_children.len
      var i = cast[int](self.range.start.int)
      if i < 0:
        i += len
      var `end` = cast[int](self.range.end.int)
      if `end` < 0:
        `end` += len
      while i < len and i <= `end`:
        if i >= 0:
          result.add(target.gene_children[i])
        i += 1
    else:
      todo("search SmByIndexRange " & $target.kind)
  of SmByName:
    case target.kind:
    of VkMap:
      if target.map.has_key(self.name):
        result.add(target.map[self.name])
    of VkInstance:
      if target.instance_props.has_key(self.name):
        result.add(target.instance_props[self.name])
    else:
      todo("search SmByName " & $target.kind)
  of SmByType:
    case target.kind:
    of VkVector:
      for item in target.vec:
        if item.kind == VkGene and item.gene_type == self.by_type:
          result.add(item)
    of VkGene:
      for item in target.gene_children:
        if item.kind == VkGene and item.gene_type == self.by_type:
          result.add(item)
    else:
      discard
  of SmSelfAndDescendants:
    result.add_self_and_descendants(target)
  of SmCallback:
    var args = new_gene_gene(Value(kind: VkNil))
    args.gene_children.add(target)
    var v = call(nil, self.callback, args)
    if v.kind == VkGene and v.gene_type.kind == VkSymbol:
      case v.gene_type.str:
      of "void":
        discard
      else:
        result.add(v)
    else:
      result.add(v)
  of SmInvoke:
    var args = new_gene_gene(Value(kind: VkNil))
    result.add(invoke(new_frame(), target, self.invoke_name, args))
  else:
    todo("search " & $self.kind)

proc search(self: SelectorItem, target: Value, r: SelectorResult) =
  case self.kind:
  of SiDefault:
    if self.is_last():
      case r.mode:
      of SrFirst:
        for m in self.matchers:
          r.first = m.search_first(target)
          r.done = true
          break
      of SrAll:
        for m in self.matchers:
          r.all.add(m.search(target))
    else:
      var items: seq[Value] = @[]
      for m in self.matchers:
        try:
          items.add(m.search(target))
        except SelectorNoResult:
          discard
      for child in self.children:
        for item in items:
          child.search(item, r)
  of SiSelector:
    self.selector.search(target, r)

proc search(self: Selector, target: Value, r: SelectorResult) =
  case r.mode:
  of SrFirst:
    for child in self.children:
      child.search(target, r)
      if r.done:
        return
  else:
    for child in self.children:
      child.search(target, r)

proc search*(self: Selector, target: Value): Value =
  try:
    if self.is_singular():
      var r = SelectorResult(mode: SrFirst)
      self.search(target, r)
      if r.done:
        result = r.first
        # TODO: invoke callbacks
      else:
        # raise new_exception(SelectorNoResult, "No result is found for the selector.")
        result = Value(kind: VkNil)
    else:
      var r = SelectorResult(mode: SrAll)
      self.search(target, r)
      result = new_gene_vec(r.all)
      # TODO: invoke callbacks
  except NoResult:
    result = Value(kind: VkNil)

proc selector_invoker*(frame: Frame, expr: var Expr): Value {.gcsafe.} =
  var expr = cast[ExSelectorInvoker](expr)
  var selector = frame.callable.selector
  var v: Value
  if expr.data != nil:
    v = eval(frame, expr.data)
  else:
    v = frame.self
  try:
    result = selector.search(v)
  except SelectorNoResult:
    todo()
    # var default_expr: Expr
    # for e in expr.gene_props:
    #   if e == "default":
    #     default_expr = e.map_val
    #     break
    # if default_expr != nil:
    #   result = eval(frame, default_expr)
    # else:
    #   raise

proc selector_arg_translator*(value: Value): Expr =
  var r = ExSelectorInvoker(
    evaluator: selector_invoker,
  )
  if value.gene_children.len > 0:
    r.data = translate(value.gene_children[0])
  return r

proc eval_selector(frame: Frame, expr: var Expr): Value =
  var selector = new_selector()
  selector.translator = selector_arg_translator
  var v = eval(frame, cast[ExSelector](expr).data)
  selector.children.add(gene_to_selector_item(v))
  new_gene_selector(selector)

proc new_ex_selector*(name: string): ExSelector =
  try:
    var index = name.parse_int()
    return ExSelector(
      evaluator: eval_selector,
      data: new_ex_literal(index),
    )
  except ValueError:
    return ExSelector(
      evaluator: eval_selector,
      data: new_ex_literal(new_gene_string(name)),
    )

proc eval_selector2*(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExSelector2](expr)
  var selector = new_selector()
  selector.translator = selector_arg_translator

  if expr.parallel_mode:
    for item in expr.data.mitems:
      var selector_item = gene_to_selector_item(eval(frame, item))
      selector.children.add(selector_item)
  else:
    var selector_item = gene_to_selector_item(eval(frame, expr.data[0]))
    selector.children.add(selector_item)

    if expr.data.len > 1:
      for item in expr.data[1..^1]:
        var item = item
        var v = eval(frame, item)
        var s = gene_to_selector_item(v)
        selector_item.children.add(s)
        selector_item = s

  new_gene_selector(selector)

proc new_ex_selector*(parallel_mode: bool, data: seq[Value]): Expr =
  if data.len == 1:
    return ExSelector(
      evaluator: eval_selector,
      data: translate(data[0]),
    )
  else:
    var r = ExSelector2(
      evaluator: eval_selector2,
      parallel_mode: parallel_mode,
    )
    for item in data:
      r.data.add(translate(item))
    return r

proc eval_invoke_selector(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExInvokeSelector](expr)
  var selector = new_selector()
  selector.translator = selector_arg_translator
  var item = SelectorItem()
  var name = eval(frame, expr.name).str
  item.matchers.add(SelectorMatcher(kind: SmInvoke, invoke_name: name))
  selector.children.add(item);
  new_gene_selector(selector)

proc new_ex_invoke_selector*(s: string): Expr =
  return ExInvokeSelector(
    evaluator: eval_invoke_selector,
    name: new_ex_literal(s),
    args: new_ex_arg(),
  )

proc new_ex_invoke_selector*(value: Value): Expr =
  var e = ExInvokeSelector(
    evaluator: eval_invoke_selector,
  )
  e.name = translate(value.gene_children[0])
  var args = new_ex_arg()
  for k, v in value.gene_props.mpairs:
    args.props[k] = translate(v)
  var is_first = true
  for item in value.gene_children.mitems:
    if is_first:
      is_first = false
      args.children.add(translate(item))
    else:
      is_first = true
  e.args = args
  return e

proc translate_selector(value: Value): Expr {.gcsafe.} =
  if value.gene_type.str == "@.":
    return new_ex_invoke_selector(value)
  else:
    var parallel_mode = value.gene_type.str == "@*"
    return new_ex_selector(parallel_mode, value.gene_children)

proc handle_item*(item: string): Expr =
  if item.starts_with("."):
    return new_ex_invoke_selector(item[1..^1])
  try:
    result = translate(item.parse_int())
  except ValueError:
    result = translate(item)

# @a/1
proc translate_csymbol_selector*(csymbol: seq[string]): Expr {.gcsafe.} =
  var r = ExSelector2(
    evaluator: eval_selector2,
  )
  r.data.add(handle_item(csymbol[0][1..^1]))
  for item in csymbol[1..^1]:
    r.data.add(handle_item(item))
  return r

proc eval_selector_invoker2*(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExSelectorInvoker2](expr)
  var value: Value
  if expr.target == nil:
    value = frame.self
  else:
    value = eval(frame, expr.target)
  var selector = eval(frame, expr.selector)
  selector.selector.search(value)

# (x ./ a b)
proc translate_invoke_selector*(value: Value): Expr {.gcsafe.} =
  var r = ExSelectorInvoker2(
    evaluator: eval_selector_invoker2,
    target: translate(value.gene_type),
  )
  r.selector = ExSelector2(
    evaluator: eval_selector2,
    parallel_mode: false,
  )
  for item in value.gene_children[1..^1]:
    cast[ExSelector2](r.selector).data.add(translate(item))
  return r

# (x ./a)
# (x ./a/0)
proc translate_invoke_selector2*(value: Value): Expr {.gcsafe.} =
  var r = ExSelectorInvoker2(
    evaluator: eval_selector_invoker2,
    target: translate(value.gene_type),
  )
  r.selector = ExSelector2(
    evaluator: eval_selector2,
    parallel_mode: false,
  )
  case value.gene_children[0].kind:
  of VkComplexSymbol:
    for item in value.gene_children[0].csymbol[1..^1]:
      cast[ExSelector2](r.selector).data.add(handle_item(item))
  else:
    todo($value.gene_children[0].kind)
  return r

# (./ a b)
proc translate_invoke_selector3*(value: Value): Expr {.gcsafe.} =
  var r = ExSelectorInvoker2(
    evaluator: eval_selector_invoker2,
  )
  r.selector = ExSelector2(
    evaluator: eval_selector2,
    parallel_mode: false,
  )
  for item in value.gene_children:
    cast[ExSelector2](r.selector).data.add(translate(item))
  return r

# (./a)
# (./a/0)
proc translate_invoke_selector4*(value: Value): Expr {.gcsafe.} =
  var r = ExSelectorInvoker2(
    evaluator: eval_selector_invoker2,
  )
  r.selector = ExSelector2(
    evaluator: eval_selector2,
    parallel_mode: false,
  )
  case value.gene_type.kind:
  of VkComplexSymbol:
    for item in value.gene_type.csymbol[1..^1]:
      cast[ExSelector2](r.selector).data.add(handle_item(item))
  else:
    todo($value.gene_type.kind)
  return r

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["@"] = translate_selector
    VM.gene_translators["@*"] = translate_selector
    VM.gene_translators["@."] = translate_selector

    VM.app.ns["$set"] = new_gene_processor(translate_set)

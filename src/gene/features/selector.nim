import tables

import ../types
import ../exprs
import ../translators

type
  ExSelector* = ref object of Expr
    data*: Expr

let NO_RESULT = new_gene_gene(new_gene_symbol("SELECTOR_NO_RESULT"))

proc search*(self: Selector, target: Value, r: SelectorResult)

proc search_first(self: SelectorMatcher, target: Value): Value =
  case self.kind:
  of SmByIndex:
    case target.kind:
    of VkVector:
      if self.index >= target.vec.len:
        return NO_RESULT
      else:
        return target.vec[self.index]
    of VkGene:
      if self.index >= target.gene_data.len:
        return NO_RESULT
      else:
        return target.gene_data[self.index]
    else:
      todo()
  of SmByName:
    case target.kind:
    of VkMap:
      if target.map.has_key(self.name):
        return target.map[self.name]
      else:
        return NO_RESULT
    of VkGene:
      if target.gene_props.has_key(self.name):
        return target.gene_props[self.name]
      else:
        return NO_RESULT
    of VkInstance:
      return target.instance.props.get_or_default(self.name, Nil)
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
  else:
    todo()

proc add_self_and_descendants(self: var seq[Value], v: Value) =
  self.add(v)
  case v.kind:
  of VkVector:
    for child in v.vec:
      self.add_self_and_descendants(child)
  of VkGene:
    for child in v.gene_data:
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
      result.add(target.gene_data[self.index])
    else:
      todo()
  of SmByName:
    case target.kind:
    of VkMap:
      result.add(target.map[self.name])
    else:
      todo()
  of SmByType:
    case target.kind:
    of VkVector:
      for item in target.vec:
        if item.kind == VkGene and item.gene_type == self.by_type:
          result.add(item)
    of VkGene:
      for item in target.gene_data:
        if item.kind == VkGene and item.gene_type == self.by_type:
          result.add(item)
    else:
      discard
  of SmSelfAndDescendants:
    result.add_self_and_descendants(target)
  # of SmCallback:
  #   var args = new_gene_gene(Nil)
  #   args.gene_data.add(target)
  #   var v = VM.call_fn(Nil, self.callback.internal.fn, args)
  #   if v.kind == VkGene and v.gene_type.kind == Symbol:
  #     case v.gene_type.symbol:
  #     of "void":
  #       discard
  #     else:
  #       result.add(v)
  #   else:
  #     result.add(v)
  else:
    todo()

proc search(self: SelectorItem, target: Value, r: SelectorResult) =
  case self.kind:
  of SiDefault:
    if self.is_last():
      case r.mode:
      of SrFirst:
        for m in self.matchers:
          var v = m.search_first(target)
          if v != NO_RESULT:
            r.done = true
            r.first = v
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
  if self.is_singular():
    var r = SelectorResult(mode: SrFirst)
    self.search(target, r)
    if r.done:
      result = r.first
      # TODO: invoke callbacks
    else:
      raise new_exception(SelectorNoResult, "No result is found for the selector.")
  else:
    var r = SelectorResult(mode: SrAll)
    self.search(target, r)
    result = new_gene_vec(r.all)
    # TODO: invoke callbacks

proc update(self: SelectorItem, target: Value, value: Value): bool =
  for m in self.matchers:
    case m.kind:
    of SmByIndex:
      case target.kind:
      of VkVector:
        if self.is_last:
          target.vec[m.index] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.vec[m.index], value)
      else:
        todo()
    of SmByName:
      case target.kind:
      of VkMap:
        if self.is_last:
          target.map[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.map[m.name], value)
      of VkGene:
        if self.is_last:
          target.gene_props[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.gene_props[m.name], value)
      of VkInstance:
        if self.is_last:
          target.instance.props[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.instance.props[m.name], value)
      else:
        todo($target.kind)
    else:
      todo()

proc update*(self: Selector, target: Value, value: Value): bool =
  for child in self.children:
    result = result or child.update(target, value)

proc selector_invoker*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExArguments](expr)
  var selector = target.selector
  var v = self.eval(frame, expr.data[0])
  try:
    result = selector.search(v)
  except SelectorNoResult:
    todo()
    # var default_expr: Expr
    # for e in expr.gene_props:
    #   if e.map_key == DEFAULT_KEY:
    #     default_expr = e.map_val
    #     break
    # if default_expr != nil:
    #   result = self.eval(frame, default_expr)
    # else:
    #   raise

proc arg_translator*(value: Value): Expr =
  var e = new_ex_arg()
  e.evaluator = selector_invoker
  for v in value.gene_data:
    e.data.add(translate(v))
  return e

proc eval_selector(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var selector = new_selector()
  var v = self.eval(frame, cast[ExSelector](expr).data)
  selector.children.add(gene_to_selector_item(v))
  result = new_gene_selector(selector)
  result.selector.translator = arg_translator

proc translate_selector(value: Value): Expr =
  ExSelector(
    evaluator: eval_selector,
    data: translate(value.gene_data[0]),
  )

proc init*() =
  GeneTranslators["@"] = translate_selector

import tables

import ./map_key
import ./types
import ./interpreter_base

let BREAK_EXPR* = Expr()
BREAK_EXPR.evaluator = proc(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e: Break
  e.new
  raise e

let CONTINUE_EXPR* = Expr()
CONTINUE_EXPR.evaluator = proc(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e: Continue
  e.new
  raise e

type
  ExSymbol* = ref object of Expr
    name*: MapKey

  ExNames* = ref object of Expr
    names*: seq[MapKey]

proc eval_names*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExNames](expr)
  case e.names[0]:
  of GLOBAL_KEY:
    result = GLOBAL_NS
  else:
    result = frame.scope[e.names[0]]

  if result == nil:
    result = frame.ns[e.names[0]]
  # for name in e.names[1..^1]:
  #   result = result.get_member(name)

proc new_ex_names*(self: Value): ExNames =
  var e = ExNames(
    evaluator: eval_names,
  )
  for s in self.csymbol:
    e.names.add(s.to_key)
  result = e

#################### Selector ####################

type
  ExSet* = ref object of Expr
    target*: Expr
    selector*: Expr
    value*: Expr

  ExInvokeSelector* = ref object of Expr
    self*: Expr
    data*: seq[Expr]

proc update(self: SelectorItem, target: Value, value: Value): bool =
  for m in self.matchers:
    case m.kind:
    of SmByIndex:
      # TODO: handle negative number
      case target.kind:
      of VkVector:
        if self.is_last:
          target.vec[m.index] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.vec[m.index], value)
      of VkGene:
        if self.is_last:
          target.gene_children[m.index] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.gene_children[m.index], value)
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
      of VkNamespace:
        if self.is_last:
          target.ns.members[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.ns.members[m.name], value)
      of VkClass:
        if self.is_last:
          target.class.ns.members[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.class.ns.members[m.name], value)
      of VkInstance:
        if self.is_last:
          target.instance_props[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.instance_props[m.name], value)
      else:
        todo($target.kind)
    else:
      todo()

proc update*(self: Selector, target: Value, value: Value): bool =
  for child in self.children:
    result = result or child.update(target, value)

proc eval_set*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExSet](expr)
  var target =
    if expr.target == nil:
      frame.self
    else:
      self.eval(frame, expr.target)
  var selector = self.eval(frame, expr.selector)
  result = self.eval(frame, expr.value)
  case selector.kind:
  of VkSelector:
    var success = selector.selector.update(target, result)
    if not success:
      todo("Update by selector failed.")
  of VkInt:
    case target.kind:
    of VkGene:
      target.gene_children[selector.int] = result
    of VkVector:
      target.vec[selector.int] = result
    else:
      todo($target.kind)
  of VkString:
    case target.kind:
    of VkGene:
      target.gene_props[selector.str] = result
    of VkMap:
      target.map[selector.str] = result
    else:
      todo($target.kind)
  else:
    todo($selector.kind)

proc translate_set*(value: Value): Expr =
  var e = ExSet(
    evaluator: eval_set,
  )
  if value.gene_children.len == 2:
    e.selector = translate(value.gene_children[0])
    e.value = translate(value.gene_children[1])
  else:
    e.target = translate(value.gene_children[0])
    e.selector = translate(value.gene_children[1])
    e.value = translate(value.gene_children[2])
  return e

#################### OOP #########################

type
  ExInvoke* = ref object of Expr
    self*: Expr
    meth*: MapKey
    args*: Expr

proc eval_invoke*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExInvoke](expr)
  var instance: Value
  var e = cast[ExInvoke](expr).self
  if e == nil:
    instance = frame.self
  else:
    instance = self.eval(frame, e)
  if instance == nil:
    raise new_exception(types.Exception, "Invoking " & expr.meth.to_s & " on nil.")

  self.invoke(frame, instance, expr.meth, expr.args)

proc translate_invoke*(value: Value): Expr =
  var r = ExInvoke(
    evaluator: eval_invoke,
  )
  r.self = translate(value.gene_props.get_or_default(SELF_KEY, nil))
  r.meth = value.gene_props[METHOD_KEY].str.to_key

  var args = new_ex_arg()
  for k, v in value.gene_props:
    args.props[k] = translate(v)
  for v in value.gene_children:
    args.children.add(translate(v))
  r.args = args

  result = r

##################################################

proc translate_arguments*(value: Value): Expr =
  var r = new_ex_arg()
  for k, v in value.gene_props:
    r.props[k] = translate(v)
  for v in value.gene_children:
    r.children.add(translate(v))
  r.check_explode()
  result = r

proc translate_arguments*(value: Value, eval: Evaluator): Expr =
  result = translate_arguments(value)
  result.evaluator = eval

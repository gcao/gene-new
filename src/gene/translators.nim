import tables

import ./map_key
import ./types
import ./exception

var Translators*     = new_table[ValueKind, Translator]()
var GeneTranslators* = new_table[string, Translator]()

proc translate*(value: Value): Expr
proc translate*(stmts: seq[Value]): Expr

proc eval_todo*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  todo()

proc eval_never*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  raise new_exception(types.Exception, "eval_never should never be called.")

#################### ExLiteral ###################

type
  ExLiteral* = ref object of Expr
    data*: Value

proc eval_literal(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  cast[ExLiteral](expr).data

proc new_ex_literal*(v: Value): ExLiteral =
  ExLiteral(
    evaluator: eval_literal,
    data: v,
  )

#################### ExString ###################

type
  ExString* = ref object of Expr
    data*: string

proc eval_string(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  return "" & cast[ExString](expr).data

proc new_ex_string*(v: Value): ExString =
  ExString(
    evaluator: eval_string,
    data: v.str,
  )

#################### ExGroup #####################

type
  ExGroup* = ref object of Expr
    children*: seq[Expr]

proc eval_group*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  for item in cast[ExGroup](expr).children.mitems:
    result = self.eval(frame, item)

proc new_ex_group*(): ExGroup =
  result = ExGroup(
    evaluator: eval_group,
  )

#################### ExExplode ###################

type
  ExExplode* = ref object of Expr
    data*: Expr

proc eval_explode*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var data = self.eval(frame, cast[ExExplode](expr).data)
  Value(
    kind: VkExplode,
    explode: data,
  )

proc new_ex_explode*(): ExExplode =
  result = ExExplode(
    evaluator: eval_explode,
  )

#################### ExSelf ######################

type
  ExSelf* = ref object of Expr

proc eval_self(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  frame.self

proc new_ex_self*(): ExSelf =
  ExSelf(
    evaluator: eval_self,
  )

#################### ExNsDef #####################

type
  ExNsDef* = ref object of Expr
    name*: MapKey
    value*: Expr

proc eval_ns_def(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExNsDef](expr)
  result = self.eval(frame, e.value)
  frame.ns[e.name] = result

proc new_ex_ns_def*(): ExNsDef =
  result = ExNsDef(
    evaluator: eval_ns_def,
  )

#################### ExGene ######################

type
  ExGene* = ref object of Expr
    `type`*: Expr
    args*: Value        # The unprocessed args
    args_expr*: Expr    # The translated args

#################### ExArguments #################

type
  ExArguments* = ref object of Expr
    has_explode*: bool
    props*: Table[MapKey, Expr]
    children*: seq[Expr]

proc eval_args*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExArguments](expr)
  result = new_gene_gene()
  for k, v in expr.props.mpairs:
    result.gene_props[k] = self.eval(frame, v)
  for _, v in expr.children.mpairs:
    var value = self.eval(frame, v)
    if value.is_nil:
      discard
    elif value.kind == VkExplode:
      for item in value.explode.vec:
        result.gene_children.add(item)
    else:
      result.gene_children.add(value)

proc new_ex_arg*(): ExArguments =
  result = ExArguments(
    evaluator: eval_args,
  )

proc check_explode*(self: var ExArguments) =
  for child in self.children:
    if child of ExExplode:
      self.has_explode = true
      return

#################### ExBreak #####################

type
  ExBreak* = ref object of Expr

proc eval_break*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e: Break
  e.new
  raise e

proc new_ex_break*(): ExBreak =
  result = ExBreak(
    evaluator: eval_break,
  )

##################################################

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

##################################################

proc default_translator(value: Value): Expr =
  case value.kind:
  of VkNil, VkBool, VkInt, VkFloat, VkRegex, VkTime:
    return new_ex_literal(value)
  of VkString:
    return new_ex_string(value)
  of VkStream:
    return translate(value.stream)
  else:
    todo($value.kind)

proc translate*(value: Value): Expr =
  var translator = Translators.get_or_default(value.kind, default_translator)
  translator(value)

proc translate*(stmts: seq[Value]): Expr =
  case stmts.len:
  of 0:
    result = new_ex_literal(nil)
  of 1:
    result = translate(stmts[0])
  else:
    result = new_ex_group()
    for stmt in stmts:
      cast[ExGroup](result).children.add(translate(stmt))

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

proc translate_catch*(value: Value): Expr =
  try:
    result = translate(value)
  except system.Exception as e:
    # echo e.msg
    # echo e.get_stack_trace()
    result = new_ex_exception(e)

proc translate_wrap*(translate: Translator): Translator =
  return proc(value: Value): Expr =
    result = translate(value)
    if result != nil and result of ExException:
      raise cast[ExException](result).ex

proc new_ex_arg*(value: Value): ExArguments =
  result = ExArguments(
    evaluator: eval_args,
  )
  for k, v in value.gene_props:
    result.props[k] = translate(v)
  for v in value.gene_children:
    result.children.add(translate(v))
  result.check_explode()

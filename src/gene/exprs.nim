import tables

import ./map_key
import ./types

#################### Expr ########################

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

#################### ExLiteral ###################

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

#################### ExSetProp ###################

type
  ExSetProp* = ref object of Expr
    name*: MapKey
    value*: Expr

proc eval_set_prop*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var value = cast[ExSetProp](expr).value
  result = self.eval(frame, value)
  frame.self.instance_props[cast[ExSetProp](expr).name] = result

proc new_ex_set_prop*(name: string, value: Expr): ExSetProp =
  ExSetProp(
    evaluator: eval_set_prop,
    name: name.to_key,
    value: value,
  )

#################### Selector ####################

type
  ExInvokeSelector* = ref object of Expr
    self*: Expr
    data*: seq[Expr]

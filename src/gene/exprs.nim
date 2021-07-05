import tables

import ./map_key
import ./types

#################### Expr ########################

proc eval_todo*(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  todo()

#################### ExLiteral ###################

type
  ExLiteral* = ref object of Expr
    data*: Value

proc eval_literal(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  cast[ExLiteral](expr).data

proc new_ex_literal*(v: Value): ExLiteral =
  ExLiteral(
    evaluator: eval_literal,
    data: v,
  )

#################### ExGroup #####################

type
  ExGroup* = ref object of Expr
    data*: seq[Expr]

proc eval_group*(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  for item in cast[ExGroup](expr).data.mitems:
    result = item.evaluator(self, frame, item)

proc new_ex_group*(): ExGroup =
  result = ExGroup(
    evaluator: eval_group,
  )

#################### ExSelf ######################

type
  ExSelf* = ref object of Expr

proc eval_self(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
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

proc eval_ns_def(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var e = cast[ExNsDef](expr)
  result = e.value.evaluator(self, frame, e.value)
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
    props*: Table[MapKey, Expr]
    data*: seq[Expr]

proc eval_args(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  todo()

proc new_ex_arg*(): ExArguments =
  result = ExArguments(
    evaluator: eval_args,
  )

#################### ExBreak #####################

type
  ExBreak* = ref object of Expr

proc eval_break*(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
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

  ExComplexSymbol* = ref object of Expr
    first*: MapKey
    rest*: seq[MapKey]

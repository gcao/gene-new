import tables

import ../map_key
import ../types
import ../translators
import ./arithmetic

type
  ExAssignment* = ref object of Expr
    name*: MapKey
    value*: Expr

proc eval_assignment(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var name = cast[ExAssignment](expr).name
  var value = cast[ExAssignment](expr).value
  result = self.eval(frame, value)
  if frame.scope.has_key(name):
    frame.scope[name] = result
  else:
    frame.ns[name] = result

proc translate_assignment(value: Value): Expr =
  result = ExAssignment(
    evaluator: eval_assignment,
    name: value.gene_data[0].symbol.to_key,
    value: translate(value.gene_data[1]),
  )
  # if value.gene_data[0].symbol[0] == "@":
  #   result = new_ex_set_prop(value.gene_data[0].symbol[1..^1], translate(value.gene_data[1]))
  # else:
  #   result = ExAssignment(
  #     evaluator: eval_assignment,
  #     name: value.gene_data[0].symbol.to_key,
  #     value: translate(value.gene_data[1]),
  #   )

proc translate_op_eq(value: Value): Expr =
  var r: ExAssignment
  case value.gene_type.symbol:
  of "+=":
    r = ExAssignment(
      evaluator: eval_assignment,
      name: value.gene_data[0].symbol.to_key,
      value: new_ex_bin(BinAdd),
    )
  of "-=":
    r = ExAssignment(
      evaluator: eval_assignment,
      name: value.gene_data[0].symbol.to_key,
      value: new_ex_bin(BinSub),
    )
  else:
    todo()

  cast[ExBinOp](r.value).op1 = translate(value.gene_data[0])
  cast[ExBinOp](r.value).op2 = translate(value.gene_data[1])
  result = r

proc init*() =
  GeneTranslators["="] = translate_assignment

  GeneTranslators["+="] = translate_op_eq
  GeneTranslators["-="] = translate_op_eq
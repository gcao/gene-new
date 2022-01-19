import tables

import ../map_key
import ../types
import ../exprs
import ../translators
import ./arithmetic
import ./symbol

# TODO: improve handling of below cases
# (a = 1)
# (a += 1)
# (@a = 1)
# (@a += 1)
# (@a/0 = 1)  # should throw error
# (@a/0 += 1) # should throw error

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
    name: value.gene_children[0].symbol.to_key,
    value: translate(value.gene_children[1]),
  )
  # if value.gene_children[0].symbol[0] == "@":
  #   result = new_ex_set_prop(value.gene_children[0].symbol[1..^1], translate(value.gene_children[1]))
  # else:
  #   result = ExAssignment(
  #     evaluator: eval_assignment,
  #     name: value.gene_children[0].symbol.to_key,
  #     value: translate(value.gene_children[1]),
  #   )

proc translate_op_eq(value: Value): Expr =
  var name = value.gene_children[0].symbol
  var value_expr: ExBinOp
  case value.gene_type.symbol:
  of "+=":
    value_expr = new_ex_bin(BinAdd)
  of "-=":
    value_expr = new_ex_bin(BinSub)
  of "*=":
    value_expr = new_ex_bin(BinMul)
  of "/=":
    value_expr = new_ex_bin(BinDiv)
  of "&&=":
    value_expr = new_ex_bin(BinAnd)
  of "||=":
    value_expr = new_ex_bin(BinOr)
  else:
    todo("translate_op_eq " & $value.gene_type.symbol)

  if value.gene_children[0].symbol[0] == '@':
    # (@a ||= x)  =>  (@a = (/@a || x))
    var selector: seq[string] = @["", value.gene_children[0].symbol]
    value_expr.op1 = translate(selector)
    value_expr.op2 = translate(value.gene_children[1])
    return new_ex_set_prop(name[1..^1], value_expr)
  else:
    value_expr.op1 = translate(value.gene_children[0])
    value_expr.op2 = translate(value.gene_children[1])
    return ExAssignment(
      evaluator: eval_assignment,
      name: name.to_key,
      value: value_expr,
    )

proc init*() =
  GeneTranslators["="] = translate_assignment

  GeneTranslators["+="] = translate_op_eq
  GeneTranslators["-="] = translate_op_eq
  GeneTranslators["*="] = translate_op_eq
  GeneTranslators["/="] = translate_op_eq
  GeneTranslators["**="] = translate_op_eq
  GeneTranslators["&&="] = translate_op_eq
  GeneTranslators["||="] = translate_op_eq

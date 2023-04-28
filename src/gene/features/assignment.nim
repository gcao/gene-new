import tables

import ../types
import ../interpreter_base
import ./arithmetic
import ./symbol

# TODO: improve handling of below cases
# (a = 1)
# (/b = 1)
# (a/b = 1)
# (a += 1)
# (@a = 1)
# (@a += 1)
# (@a/0 = 1)  # should throw error
# (@a/0 += 1) # should throw error

type
  ExAssignment* = ref object of Expr
    name*: string
    value*: Expr

proc eval_assignment(frame: Frame, expr: var Expr): Value =
  var name = cast[ExAssignment](expr).name
  var value = cast[ExAssignment](expr).value
  result = eval(frame, value)
  if frame.scope.has_key(name):
    frame.scope[name] = result
  else:
    frame.ns[name] = result

proc translate_assignment(value: Value): Expr {.gcsafe.} =
  var first = value.gene_children[0]
  case first.kind:
  of VkSymbol:
    result = ExAssignment(
      evaluator: eval_assignment,
      name: first.str,
      value: translate(value.gene_children[1]),
    )
  of VkComplexSymbol:
    var e = ExSet(
      evaluator: eval_set,
    )
    e.target = translate(first.csymbol[0..^2])
    e.selector = translate(new_gene_symbol("@" & first.csymbol[^1]))
    e.value = translate(value.gene_children[1])
    return e
  else:
    not_allowed("translate_assignment " & $first.kind)

proc translate_op_eq(value: Value): Expr {.gcsafe.} =
  var first = value.gene_children[0]
  var second = value.gene_children[1]
  var value_expr: ExBinOp
  case value.gene_type.str:
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
    todo("translate_op_eq " & $value.gene_type.str)

  case first.kind:
  of VkSymbol:
    value_expr.op1 = translate(first)
    value_expr.op2 = translate(second)
    return ExAssignment(
      evaluator: eval_assignment,
      name: first.str,
      value: value_expr,
    )
  of VkComplexSymbol:
    value_expr.op1 = translate(first)
    value_expr.op2 = translate(second)
    var e = ExSet(
      evaluator: eval_set,
    )
    e.target = translate(first.csymbol[0..^2])
    e.selector = translate(new_gene_symbol("@" & first.csymbol[^1]))
    e.value = value_expr
    return e
  else:
    not_allowed("translate_op_eq " & $value)

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["="] = translate_assignment

    VM.gene_translators["+="] = translate_op_eq
    VM.gene_translators["-="] = translate_op_eq
    VM.gene_translators["*="] = translate_op_eq
    VM.gene_translators["/="] = translate_op_eq
    VM.gene_translators["**="] = translate_op_eq
    VM.gene_translators["&&="] = translate_op_eq
    VM.gene_translators["||="] = translate_op_eq

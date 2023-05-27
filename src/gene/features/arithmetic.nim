import tables

import ../types
import ../interpreter_base

const BINARY_OPS* = [
  "+", "-", "*", "/", "**",
  "=~", "!~",
  # "==", "!=", "<", "<=", ">", ">=",
  # "&&", "||",         # TODO: if we support XOR with ||*, what's its precedence against AND and OR?
  # "&",  "|",          # TODO: xor for bit operation
  # ">>", "<<",         # >>: shift right, <<: shift left
]

const COMPARISON_OPS* = [
  "==", "!=", "<", "<=", ">", ">=",
]

const LOGIC_OPS* = [
  "&&", "||",
]

# const BINARY_OP_SHORTCUTS* = [
#   "=", "+=", "-=", "*=", "/=", "**=",
#   "&&=", "||=",
#   "&=", "|=",
# ]

const PRECEDENCES* = {
  "+": 1,
  "-": 1,

  "*": 2,
  "/": 2,

  "**": 3,

  "||": 1,
  "&&": 2,
}.toTable()

type
  BinOp* = enum
    BinAdd
    BinSub
    BinMul
    BinDiv
    BinPow
    BinEq
    BinNeq
    BinLt
    BinLe
    BinGt
    BinGe
    BinAnd
    BinOr

  ExBinOp* = ref object of Expr
    op*: BinOp
    op1*: Expr
    op2*: Expr

  ExAnd* = ref object of Expr
    children*: seq[Expr]

proc eval_bin(frame: Frame, expr: var Expr): Value =
  var first = eval(frame, cast[ExBinOp](expr).op1)
  var second = eval(frame, cast[ExBinOp](expr).op2)
  case cast[ExBinOp](expr).op:
  of BinAdd:
    result = new_gene_int(first.int + second.int)
  of BinSub:
    case first.kind:
    of VkInt:
      result = new_gene_int(first.int - second.int)
    else:
      todo($first.kind)
      # var class = first.get_class()
      # var args = new_gene_gene(GeneNil)
      # args.gene_children.add(second)
      # result = self.call_method(frame, first, class, SUB_KEY, args)
  of BinMul:
    result = new_gene_int(first.int * second.int)
  of BinDiv:
    result = new_gene_float(first.int / second.int)
  of BinEq:
    result = new_gene_bool(first == second)
  of BinNeq:
    result = new_gene_bool(first != second)
  of BinLt:
    result = new_gene_bool(first.int < second.int)
  of BinLe:
    result = new_gene_bool(first.int <= second.int)
  of BinGt:
    result = new_gene_bool(first.int > second.int)
  of BinGe:
    result = new_gene_bool(first.int >= second.int)
  else:
    todo("eval_bin " & $cast[ExBinOp](expr).op)

proc eval_logical(frame: Frame, expr: var Expr): Value =
  var op = cast[ExBinOp](expr).op
  var first = eval(frame, cast[ExBinOp](expr).op1)
  case op:
  of BinAnd:
    if first.is_truthy:
      result = eval(frame, cast[ExBinOp](expr).op2)
    else:
      result = first
  of BinOr:
    if first.is_truthy:
      result = first
    else:
      result = eval(frame, cast[ExBinOp](expr).op2)
  else:
    not_allowed("eval_logical " & $op)

proc new_ex_bin*(op: BinOp): ExBinOp =
  case op:
  of BinAnd, BinOr:
    ExBinOp(
      evaluator: eval_logical,
      op: op,
    )
  else:
    ExBinOp(
      evaluator: eval_bin,
      op: op,
    )

proc translate_op*(op: string, op1, op2: Expr): Expr {.gcsafe.} =
  case op:
  of "+":
    result = new_ex_bin(BinAdd)
  of "-":
    result = new_ex_bin(BinSub)
  of "*":
    result = new_ex_bin(BinMul)
  of "/":
    result = new_ex_bin(BinDiv)
  of "==":
    result = new_ex_bin(BinEq)
  of "!=":
    result = new_ex_bin(BinNeq)
  of "<":
    result = new_ex_bin(BinLt)
  of "<=":
    result = new_ex_bin(BinLe)
  of ">":
    result = new_ex_bin(BinGt)
  of ">=":
    result = new_ex_bin(BinGe)
  of "&&":
    result = new_ex_bin(BinAnd)
  of "||":
    result = new_ex_bin(BinOr)
  else:
    todo("translate_op " & op)

  cast[ExBinOp](result).op1 = op1
  cast[ExBinOp](result).op2 = op2

proc translate_arithmetic*(value: Value): Expr {.gcsafe.} =
  case value.gene_type.str:
  of "+":
    result = new_ex_bin(BinAdd)
  of "-":
    result = new_ex_bin(BinSub)
  of "*":
    result = new_ex_bin(BinMul)
  of "/":
    result = new_ex_bin(BinDiv)
  of "==":
    result = new_ex_bin(BinEq)
  of "!=":
    result = new_ex_bin(BinNeq)
  of "<":
    result = new_ex_bin(BinLt)
  of "<=":
    result = new_ex_bin(BinLe)
  of ">":
    result = new_ex_bin(BinGt)
  of ">=":
    result = new_ex_bin(BinGe)
  of "&&":
    result = new_ex_bin(BinAnd)
  of "||":
    result = new_ex_bin(BinOr)

  cast[ExBinOp](result).op1 = translate(value.gene_children[0])
  cast[ExBinOp](result).op2 = translate(value.gene_children[1])

proc translate_arithmetic*(children: seq[Value]): Expr {.gcsafe.} =
  if children.len == 1:
    return translate(children[0])
  elif children.len == 3:
    return translate_op(children[1].str, translate(children[0]), translate(children[2]))
  elif children.len > 3:
    # TODO: validate combination of operators
    var lowest_precedence_index = 1
    var lowest_precedence_op = children[lowest_precedence_index].str
    var i = lowest_precedence_index + 2
    while i < children.len:
      var op = children[i].str
      if PRECEDENCES[lowest_precedence_op] > PRECEDENCES[op]:
        lowest_precedence_index = i
        lowest_precedence_op = op
      i += 2
    return translate_op(
      lowest_precedence_op,
      translate_arithmetic(children[0..lowest_precedence_index-1]),
      translate_arithmetic(children[lowest_precedence_index+1..^1]))
  else:
    not_allowed("translate_arithmetic " & $children)

proc eval_and(frame: Frame, expr: var Expr): Value =
  for e in cast[ExAnd](expr).children.mitems:
    if not eval(frame, e):
      return false
  return true

proc translate_comparisons*(children: seq[Value]): Expr {.gcsafe.} =
  if children.len == 1:
    return translate(children[0])
  elif children.len == 3:
    return translate_op(children[1].str, translate(children[0]), translate(children[2]))
  elif children.len > 3:
    var r = ExAnd(evaluator: eval_and)
    var i = 1
    while i < children.len - 1:
      r.children.add(translate_op(children[i].str, translate(children[i-1]), translate(children[i+1])))
      i += 2
    return r
  else:
    not_allowed("translate_comparisons " & $children)

proc translate_logic*(children: seq[Value]): Expr {.gcsafe.} =
  if children.len == 1:
    return translate(children[0])
  elif children.len == 3:
    return translate_op(children[1].str, translate(children[0]), translate(children[2]))
  elif children.len > 3:
    # TODO: validate combination of operators
    var lowest_precedence_index = 1
    var lowest_precedence_op = children[lowest_precedence_index].str
    var i = lowest_precedence_index + 2
    while i < children.len:
      var op = children[i].str
      if PRECEDENCES[lowest_precedence_op] > PRECEDENCES[op]:
        lowest_precedence_index = i
        lowest_precedence_op = op
      i += 2
    return translate_op(
      lowest_precedence_op,
      translate_logic(children[0..lowest_precedence_index-1]),
      translate_logic(children[lowest_precedence_index+1..^1]))
  else:
    not_allowed("translate_logic " & $children)

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["+"  ] = translate_arithmetic
    VM.gene_translators["-"  ] = translate_arithmetic
    VM.gene_translators["*"  ] = translate_arithmetic
    VM.gene_translators["/"  ] = translate_arithmetic
    VM.gene_translators["**" ] = translate_arithmetic # power
    VM.gene_translators[">>" ] = translate_arithmetic # shift right
    VM.gene_translators["<<" ] = translate_arithmetic # shift left
    VM.gene_translators["&"  ] = translate_arithmetic  # bit-and
    VM.gene_translators["|"  ] = translate_arithmetic  # bit-or
    VM.gene_translators["==" ] = translate_arithmetic
    VM.gene_translators["!=" ] = translate_arithmetic
    VM.gene_translators["<"  ] = translate_arithmetic
    VM.gene_translators["<=" ] = translate_arithmetic
    VM.gene_translators[">"  ] = translate_arithmetic
    VM.gene_translators[">=" ] = translate_arithmetic
    VM.gene_translators["&&" ] = translate_arithmetic
    VM.gene_translators["||" ] = translate_arithmetic
    VM.gene_translators["||*"] = translate_arithmetic  # xor

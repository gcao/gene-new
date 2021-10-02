import tables

import ../types
import ../translators

type
  BinOp* = enum
    BinAdd
    BinSub
    BinMul
    BinDiv
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

proc eval_bin(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var first = self.eval(frame, cast[ExBinOp](expr).op1)
  var second = self.eval(frame, cast[ExBinOp](expr).op2)
  case cast[ExBinOp](expr).op:
  of BinAdd:
    result = new_gene_int(first.int + second.int)
  of BinSub:
    result = new_gene_int(first.int - second.int)
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
  of BinAnd:
    result = new_gene_bool(first.bool and second.bool)
  of BinOr:
    result = new_gene_bool(first.bool or second.bool)
  else:
    todo()

proc new_ex_bin*(op: BinOp): ExBinOp =
  ExBinOp(
    evaluator: eval_bin,
    op: op,
  )

proc translate_arithmetic*(value: Value): Expr =
  case value.gene_type.symbol:
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

  cast[ExBinOp](result).op1 = translate(value.gene_data[0])
  cast[ExBinOp](result).op2 = translate(value.gene_data[1])

proc init*() =
  GeneTranslators["+"] = translate_arithmetic
  GeneTranslators["-"] = translate_arithmetic
  GeneTranslators["*"] = translate_arithmetic
  GeneTranslators["/"] = translate_arithmetic
  GeneTranslators["=="] = translate_arithmetic
  GeneTranslators["<"] = translate_arithmetic
  GeneTranslators["<="] = translate_arithmetic
  GeneTranslators[">"] = translate_arithmetic
  GeneTranslators[">="] = translate_arithmetic
  GeneTranslators["&&"] = translate_arithmetic
  GeneTranslators["||"] = translate_arithmetic

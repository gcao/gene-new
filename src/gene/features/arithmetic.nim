import tables

import ../types
import ../translators
import ../interpreter

proc translate_arithmetic(value: Value): Value =
  case value.gene_type.symbol:
  of "+":
    result = Value(kind: VkExBinOp)
    result.ex_bin_op = BinAdd
  of "-":
    result = Value(kind: VkExBinOp)
    result.ex_bin_op = BinSub
  of "*":
    result = Value(kind: VkExBinOp)
    result.ex_bin_op = BinMul
  of "/":
    result = Value(kind: VkExBinOp)
    result.ex_bin_op = BinDiv
  of "==":
    result = Value(kind: VkExBinOp)
    result.ex_bin_op = BinEq
  of "!=":
    result = Value(kind: VkExBinOp)
    result.ex_bin_op = BinNeq
  of "<":
    result = Value(kind: VkExBinOp)
    result.ex_bin_op = BinLt
  of "<=":
    result = Value(kind: VkExBinOp)
    result.ex_bin_op = BinLe
  of ">":
    result = Value(kind: VkExBinOp)
    result.ex_bin_op = BinGt
  of ">=":
    result = Value(kind: VkExBinOp)
    result.ex_bin_op = BinGe
  of "&&":
    result = Value(kind: VkExBinOp)
    result.ex_bin_op = BinAnd
  of "||":
    result = Value(kind: VkExBinOp)
    result.ex_bin_op = BinOr

  result.ex_bin_op1 = translate(value.gene_data[0])
  result.ex_bin_op2 = translate(value.gene_data[1])

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

  Evaluators[VkExBinOp.ord] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    var first = self.eval(frame, expr.ex_bin_op1)
    var second = self.eval(frame, expr.ex_bin_op2)
    case expr.ex_bin_op:
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

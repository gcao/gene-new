import tables

import ../types
import ../translators
# import ../interpreter

type
  ExEnum* = ref object of Expr
    data*: Value

proc eval_enum(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  result = cast[ExEnum](expr).data
  frame.ns[result.enum.name] = result

proc translate_enum(value: Value): Expr =
  var r = ExEnum(
    evaluator: eval_enum,
  )
  var e = new_enum(value.gene_data[0].symbol_or_str)
  var i = 1
  var v = 0
  while i < value.gene_data.len:
    var name = value.gene_data[i].symbol
    i += 1
    if i < value.gene_data.len and value.gene_data[i] == Equal:
      i += 1
      v = value.gene_data[i].int
      i += 1
    e.add_member(name, v)
    v += 1

  r.data = Value(kind: VkEnum, `enum`: e)
  return r

proc init*() =
  GeneTranslators["enum"] = translate_enum
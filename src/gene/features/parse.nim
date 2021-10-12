import tables

import ../types
import ../translators
import ../parser

type
  ExParse* = ref object of Expr
    data*: Expr

proc eval_parse(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var s = self.eval(frame, cast[ExParse](expr).data).str
  var vals = read_all(s)
  if vals.len == 0:
    result = Nil
  elif vals.len == 1:
    result = vals[0]
  else:
    result = new_gene_stream(vals)

proc translate_parse(value: Value): Expr =
  var r = ExParse(
    evaluator: eval_parse,
    data: translate(value.gene_data[0])
  )
  result = r

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    GLOBAL_NS.ns["$parse"] = new_gene_processor(translate_parse)

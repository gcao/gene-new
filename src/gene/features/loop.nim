import tables

import ../map_key
import ../types
import ../exprs
import ../translators

type
  ExLoop* = ref object of Expr
    data*: seq[Expr]

  ExContinue* = ref object of Expr

  ExOnce* = ref object of Expr
    code*: seq[Expr]
    value*: Value

let LOOP_KEY* = add_key("loop")

proc eval_loop(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  while true:
    try:
      for item in cast[ExLoop](expr).data.mitems:
        result = self.eval(frame, item)
    except Continue:
      discard
    except Break as b:
      result = b.val
      break

proc translate_loop(value: Value): Expr =
  var r = ExLoop(
    evaluator: eval_loop,
  )
  for item in value.gene_data:
    r.data.add translate(item)
  result = r

proc translate_break(value: Value): Expr =
  new_ex_break()

proc eval_continue(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e: Continue
  e.new
  raise e

proc translate_continue(value: Value): Expr =
  result = ExContinue(
    evaluator: eval_continue,
  )

proc eval_once(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  result = cast[ExOnce](expr).value
  if result == nil:
    for item in cast[ExOnce](expr).code.mitems:
      result = self.eval(frame, item)
    if result == nil:
      result = Nil
    cast[ExOnce](expr).value = result

proc translate_once(value: Value): Expr =
  var r = ExOnce(
    evaluator: eval_once,
  )
  for item in value.gene_data:
    r.code.add(translate(item))
  result = r

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    self.app.ns["loop"] = new_gene_processor(translate_loop)
    self.app.ns["break"] = new_gene_processor(translate_break)
    self.app.ns["$once"] = new_gene_processor(translate_once)

  GeneTranslators["continue"] = translate_continue

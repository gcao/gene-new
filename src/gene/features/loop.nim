import tables

import ../map_key
import ../types
import ../exprs
import ../translators

type
  ExLoop* = ref object of Expr
    data: seq[Expr]

  ExContinue* = ref object of Expr

let LOOP_KEY* = add_key("loop")

proc eval_loop(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  while true:
    try:
      for item in cast[ExLoop](expr).data.mitems:
        result = item.evaluator(self, frame, nil, item)
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

proc invoke_loop(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  self.eval_loop(frame, nil, cast[ExGene](expr).args_expr)

let LOOP_PROCESSOR* = Value(
  kind: VkGeneProcessor,
  gene_processor: GeneProcessor(
    translator: translate_loop,
    invoker: invoke_loop,
  ))

proc translate_break(value: Value): Expr =
  new_ex_break()

proc invoke_break(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  self.eval_break(frame, nil, cast[ExGene](expr).args_expr)

let BREAK_PROCESSOR* = Value(
  kind: VkGeneProcessor,
  gene_processor: GeneProcessor(
    translator: translate_break,
    invoker: invoke_break,
  ))

proc eval_continue(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e: Continue
  e.new
  raise e

proc translate_continue(value: Value): Expr =
  result = ExContinue(
    evaluator: eval_continue,
  )

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    self.app.ns["loop"] = LOOP_PROCESSOR
    self.app.ns["break"] = BREAK_PROCESSOR

  GeneTranslators["continue"] = translate_continue

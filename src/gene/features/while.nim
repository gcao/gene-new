import tables

import ../types
import ../exprs
import ../translators
import ../interpreter

type
  ExWhile* = ref object of Expr
    cond*: Expr
    body: seq[Expr]

proc eval_while(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  while true:
    var cond = self.eval(frame, cast[ExWhile](expr).cond)
    if not cond.bool:
      break
    try:
      for item in cast[ExWhile](expr).body.mitems:
        result = item.evaluator(self, frame, item)
    except Continue:
      discard
    except Break as b:
      result = b.val
      break

proc translate_while(value: Value): Expr =
  var r = ExWhile(
    evaluator: eval_while,
  )
  r.cond = translate(value.gene_data[0])
  for item in value.gene_data[1..^1]:
    r.body.add translate(item)
  result = r

proc invoke_while(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  self.eval_while(frame, cast[ExGene](expr).args_expr)

let WHILE_PROCESSOR* = Value(
  kind: VkGeneProcessor,
  gene_processor: GeneProcessor(
    translator: translate_while,
    invoker: invoke_while,
  ))

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    self.app.ns["while"] = WHILE_PROCESSOR

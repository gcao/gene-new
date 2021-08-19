import tables

import ../types
import ../exprs
import ../translators
import ../interpreter

type
  ExFor* = ref object of Expr
    key: string
    val: string
    use_key: bool
    use_val: bool
    data: Expr
    body: seq[Expr]

proc eval_for(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  todo()

proc translate_for(value: Value): Expr =
  var r = ExFor(
    evaluator: eval_for,
  )
  todo()
  result = r

proc invoke_for(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  self.eval_for(frame, cast[ExGene](expr).args_expr)

let FOR_PROCESSOR* = Value(
  kind: VkGeneProcessor,
  gene_processor: GeneProcessor(
    translator: translate_for,
    invoker: invoke_for,
  ))

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    self.app.ns["for"] = FOR_PROCESSOR

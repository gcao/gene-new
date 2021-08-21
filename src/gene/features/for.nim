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

proc eval_for(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  todo()

proc translate_for(value: Value): Expr =
  # var r = ExFor(
  #   evaluator: eval_for,
  # )
  # result = r
  todo()

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    self.app.ns["for"] = new_gene_processor(translate_for)

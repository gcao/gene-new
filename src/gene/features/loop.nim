import tables

import ../types
import ../interpreter_base

type
  ExLoop* = ref object of Expr
    data*: seq[Expr]

  ExOnce* = ref object of Expr
    input*: Value
    code*: seq[Expr]

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
  for item in value.gene_children:
    r.data.add translate(item)
  result = r

proc translate_break(value: Value): Expr =
  BREAK_EXPR

proc translate_continue(value: Value): Expr =
  CONTINUE_EXPR

proc eval_once(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExOnce](expr)
  if expr.input.gene_props.has_key("return"):
    result = expr.input.gene_props["return"]
  else:
    for item in expr.code.mitems:
      result = self.eval(frame, item)
    expr.input.gene_props["return"] = result

proc translate_once(value: Value): Expr =
  var r = ExOnce(
    evaluator: eval_once,
    input: value,
  )
  for item in value.gene_children:
    r.code.add(translate(item))
  result = r

proc init*() =
  GeneTranslators["loop"] = translate_loop
  GeneTranslators["break"] = translate_break
  GeneTranslators["continue"] = translate_continue

  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    self.global_ns.ns["$once"] = new_gene_processor(translate_once)

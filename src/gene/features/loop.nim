import tables

import ../map_key
import ../types
import ../interpreter_base

type
  ExLoop* = ref object of Expr
    data*: seq[Expr]

  ExOnce* = ref object of Expr
    input*: Value
    code*: seq[Expr]

let LOOP_KEY* = add_key("loop")

proc eval_loop(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value {.gcsafe.} =
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
  {.cast(gcsafe).}:
    BREAK_EXPR

proc translate_continue(value: Value): Expr =
  {.cast(gcsafe).}:
    CONTINUE_EXPR

proc eval_once(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value {.gcsafe.} =
  var expr = cast[ExOnce](expr)
  if expr.input.gene_props.has_key(RETURN_KEY):
    result = expr.input.gene_props[RETURN_KEY]
  else:
    for item in expr.code.mitems:
      result = self.eval(frame, item)
    expr.input.gene_props[RETURN_KEY] = result

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

  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    self.app.ns["$once"] = new_gene_processor(translate_once)

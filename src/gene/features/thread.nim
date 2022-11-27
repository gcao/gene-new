import tables
import threadpool

import ../types
import ../interpreter_base

type
  ExSpawn* = ref object of Expr
    body: seq[Expr]

proc handle_spawn(): Value =
  todo()

proc eval_spawn(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var r = spawn handle_spawn()
  ^r

proc translate_spawn(value: Value): Expr =
  var r = ExSpawn(
    evaluator: eval_spawn,
  )
  for item in value.gene_children[1..^1]:
    r.body.add translate(item)
  result = r

proc init*() =
  GeneTranslators["spawn"] = translate_spawn

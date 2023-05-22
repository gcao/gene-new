import ../types
import ../repl
import ../interpreter_base

type
  ExRepl* = ref object of Expr

proc eval_repl(frame: Frame, expr: var Expr): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    repl(frame, eval, true)

proc translate_repl(value: Value): Expr {.gcsafe.} =
  ExRepl(
    evaluator: eval_repl,
  )

proc init*() =
  VmCreatedCallbacks.add proc() =
    let repl = new_gene_processor(translate_repl)
    VM.global_ns.ns["repl"] = repl
    VM.gene_ns.ns["repl"] = repl

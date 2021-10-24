import strutils
import noise  # https://github.com/jangko/nim-noise

import ../types
# import ../repl
import ../interpreter

type
  # ExRepl* = ref object of Expr

  Eval = proc(self: VirtualMachine, frame: Frame, code: string): Value

proc print_help() =
  todo()

proc repl*(self: VirtualMachine, frame: Frame, eval: Eval, return_value: bool): Value =
  var noise = Noise.init()

  let prompt = Styler.init(fgGreen, "GENE> ")
  noise.setPrompt(prompt)

  when promptPreloadBuffer:
    discard

  when promptHistory:
    var file = "history"
    discard noise.historyLoad(file)

  when promptCompletion:
    proc completionHook(noise: var Noise, text: string): int =
      const words = ["apple", "diamond", "diadem", "diablo", "horse", "home", "quartz", "quit"]
      for w in words:
        if w.find(text) != -1:
          noise.addCompletion w

    noise.setCompletionHook(completionHook)

  while true:
    let ok = noise.readLine()
    if not ok:
      break

    let line = noise.getLine
    case line
    of "help":
      printHelp()
    of "quit":
      break
    else:
      discard

    when promptHistory:
      if line.len > 0:
        noise.historyAdd(line)

  when promptHistory:
    discard noise.historySave(file)

proc eval_repl(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  self.repl(frame, eval, true)

let EX_REPL = Expr(evaluator: eval_repl)

proc translate_repl(value: Value): Expr =
  # ExRepl(
  #   evaluator: eval_repl,
  # )
  EX_REPL

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    GLOBAL_NS.ns["repl"] = new_gene_processor(translate_repl)
    GENE_NS.ns["repl"] = GLOBAL_NS.ns["repl"]

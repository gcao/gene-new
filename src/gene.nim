import os

import ./gene/commands/base

let CommandMgr = CommandManager()

import "./gene/commands/run" as run_cmd; run_cmd.init(CommandMgr)
import "./gene/commands/eval" as eval_cmd; eval_cmd.init(CommandMgr)
import "./gene/commands/repl" as repl_cmd; repl_cmd.init(CommandMgr)

import "./gene/commands/project" as project_cmd; project_cmd.init(CommandMgr)

when isMainModule:
  var args = command_line_params()
  var cmd = args[0]
  args.delete(0)
  var handler = CommandMgr[cmd]
  discard handler(cmd, args)

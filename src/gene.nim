import os, strutils

import ./gene/commands/base

let CommandMgr = CommandManager()

import "./gene/commands/run" as run_cmd; run_cmd.init(CommandMgr)
import "./gene/commands/eval" as eval_cmd; eval_cmd.init(CommandMgr)
import "./gene/commands/repl" as repl_cmd; repl_cmd.init(CommandMgr)

import "./gene/commands/project" as project_cmd; project_cmd.init(CommandMgr)

const HELP = """Usage: gene <command> <optional arguments specific to command>

Available commands:
"""

when isMainModule:
  var args = command_line_params()
  if args.len == 0:
    echo HELP
    echo CommandMgr.help
  else:
    var cmd = args[0]
    var handler = CommandMgr[cmd]
    if cmd.ends_with(".gene") or handler.is_nil:
      cmd = "run"
      handler = CommandMgr[cmd]
    else:
      args.delete(0)
    discard handler(cmd, args)

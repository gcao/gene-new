import tables, os, parseopt

import ../types
import ../interpreter
import ./base

const DEFAULT_COMMAND = "eval"
const COMMANDS = @[DEFAULT_COMMAND]

type
  Options = ref object
    debugging: bool
    code: string

proc handle*(cmd: string, args: seq[string]): string

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("eval '<code>': parse and execute <code>")

let short_no_val = {'d'}
let long_no_val: seq[string] = @[]

proc parse_options(): Options =
  result = Options()
  for kind, key, value in get_opt(command_line_params(), short_no_val, long_no_val):
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "d", "debug":
        result.debugging = true
      else:
        echo "Unknown option: ", key
        discard
    of cmdArgument:
      result.code = key
    of cmdEnd:
      discard

proc handle*(cmd: string, args: seq[string]): string =
  var options = parse_options()
  setup_logger(options.debugging)

  init_app_and_vm()
  var frame = VM.eval_prepare(VM.app.pkg)
  VM.main_module = frame.ns.module
  discard VM.eval(frame, options.code)

when isMainModule:
  var cmd = DEFAULT_COMMAND
  var args: seq[string] = @[]
  var status = handle(cmd, args)
  if status.len > 0:
    echo "Failed with error: " & status

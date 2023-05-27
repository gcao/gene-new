import parseopt, sequtils

import ../types
import ../interpreter
import ../repl
import ./base

const DEFAULT_COMMAND = "repl"
const COMMANDS = @[DEFAULT_COMMAND]

type
  Options = ref object
    debugging: bool

proc handle*(cmd: string, args: seq[string]): string

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("repl: start an interactive REPL session")

let short_no_val = {'d'}
let long_no_val: seq[string] = @[]

proc parse_options(args: seq[string]): Options =
  result = Options()
  for kind, key, value in get_opt(args, short_no_val, long_no_val):
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "d", "debug":
        result.debugging = true
      else:
        echo "Unknown option: ", key
        discard
    of cmdArgument:
      discard
    of cmdEnd:
      discard

proc handle*(cmd: string, args: seq[string]): string =
  var options = parse_options(args)
  setup_logger(options.debugging)

  init_app_and_vm()
  VM.app.args = @["<repl>"].concat(args)
  var frame = eval_prepare(VM.app.pkg)
  discard repl(frame, eval, false)

when isMainModule:
  var cmd = DEFAULT_COMMAND
  var args: seq[string] = @[]
  var status = handle(cmd, args)
  if status.len > 0:
    echo "Failed with error: " & status

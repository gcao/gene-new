import tables, os, parseopt, times

import ../types
import ../interpreter
import ./base

type
  Options = ref object
    benchmark: bool
    debugging: bool
    print_result: bool
    repl_on_error: bool
    file: string

proc run*(cmd: string, args: seq[string]): string

proc init*(manager: CommandManager) =
  manager.data["run"] = run

let short_no_val = {'d'}
let long_no_val = @[
  "repl-on-error",
]
proc parse_options(): Options =
  result = Options()
  for kind, key, value in get_opt(command_line_params(), short_no_val, long_no_val):
    case kind
    of cmdArgument:
      result.file = key
    of cmdLongOption, cmdShortOption:
      case key
      of "d", "debug":
        result.debugging = true
      else:
        echo "Unknown option: ", key
        discard
    of cmdEnd:
      discard

proc run*(cmd: string, args: seq[string]): string =
  var options = parse_options()
  setup_logger(options.debugging)

  init_app_and_vm()
  VM.repl_on_error = options.repl_on_error

  var file = options.file
  let start = cpu_time()
  let value = VM.run_file(file)
  if options.print_result:
    echo value.to_s
  if options.benchmark:
    echo "Time: " & $(cpu_time() - start)

when isMainModule:
  var cmd = "run"
  var args: seq[string] = @[]
  var status = run(cmd, args)
  if status.len > 0:
    echo "Failed with error: " & status

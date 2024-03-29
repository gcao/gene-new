import parseopt

import ../types
import ../interpreter
import ./base

# gpro = Gene Project
# Support commands related to managing a Gene project
# E.g.
#   init - initialize a project
#   build - compile and run any custom tasks defined to build the project
#   test - run the test suite

const DEFAULT_COMMAND = "project"
const COMMANDS = @[
  DEFAULT_COMMAND,
  "init",
  "build",
  "clean",
  "test",
]

type
  Options = ref object
    debugging: bool
    code: string

proc handle*(cmd: string, args: seq[string]): string

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("\nProject related commands\ninit: initialize a project\nbuild: build the project\nclean: remove generated assets\n")

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
      result.code = key
    of cmdEnd:
      discard

proc handle*(cmd: string, args: seq[string]): string =
  var options = parse_options(args)
  setup_logger(options.debugging)

  init_app_and_vm()
  echo "TODO: " & cmd

when isMainModule:
  var cmd = DEFAULT_COMMAND
  var args: seq[string] = @[]
  var status = handle(cmd, args)
  if status.len > 0:
    echo "Failed with error: " & status

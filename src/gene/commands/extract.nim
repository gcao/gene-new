import parseopt, tables, os, strutils

import ../types
import ../parser
import ./base

const DEFAULT_COMMAND = "extract"
const COMMANDS = @[DEFAULT_COMMAND]

type
  Options = ref object
    debugging: bool

proc handle*(cmd: string, args: seq[string]): string

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("extract: Extract a Gene archive file (x.gar) to current directory or a target directory.")

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

proc handle(dir: string, value: Value) =
  var path = value.file_path()
  path = dir & path[(path.find("/") + 1)..^1]
  case value.kind:
  of VkFile:
    write_file(path, value.file_content.str)
  of VkArchiveFile:
    write_file(path, $value)
  of VkDirectory:
    create_dir(path)
    for child in value.dir_members.values():
      handle(dir, child)
  else:
    not_allowed("handle " & $value)

proc handle*(cmd: string, args: seq[string]): string =
  var options = parse_options(args)
  setup_logger(options.debugging)
  var parser = new_parser()
  var arc_file = parser.read_archive_file(args[0])
  var dir = "./"
  if args.len > 1:
    dir = args[1]
  for child in arc_file.arc_file_members.values():
    handle(dir, child)

when isMainModule:
  var cmd = DEFAULT_COMMAND
  var args: seq[string] = @[]
  var status = handle(cmd, args)
  if status.len > 0:
    echo "Failed with error: " & status

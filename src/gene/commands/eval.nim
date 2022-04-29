import parseopt, sequtils, parsecsv, streams, re

import ../map_key
import ../types
import ../parser
import ../interpreter
import ./base

const DEFAULT_COMMAND = "eval"
const COMMANDS = @[DEFAULT_COMMAND]

type
  InputMode* = enum
    ImDefault
    ImCsv
    ImGene
    ImLine

  Options* = ref object
    debugging*: bool
    repl_on_error*: bool
    code*: string
    # snippets are wrapped like (do <snippet>) and can be accessed from anywhere
    snippets*: seq[string]
    # `include` is different from `import`.
    # `include` is like inserting content of one file in another.
    includes*: seq[string]
    print_result*: bool
    filter_result*: bool
    input_mode*: InputMode
    skip_first*: bool
    skip_empty*: bool
    index_name*: string
    value_name*: string

let shortNoVal = {'d'}
let longNoVal = @[
  "repl-on-error",
  "debug",
  "print-result", "pr",
  "filter-result", "fr",
  "skip-first-line", "sf",
  "skip-empty-line", "se",
  "csv",
  "gene",
  "line",
]

proc handle*(cmd: string, args: seq[string]): string

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("eval '<code>': parse and execute <code>")

# When running like
# <PROGRAM> --debug test.gene 1 2 3
# test.gene is invoked with 1, 2, 3 as argument
#
# When running like
# <PROGRAM> --debug -- 1 2 3
# 1, 2, 3 are passed as argument to REPL
proc parse_options(args: seq[string]): Options =
  result = Options(
    index_name: "i",
    value_name: "v",
  )
  for kind, key, value in getOpt(args, shortNoVal, longNoVal):
    case kind
    of cmdArgument:
      result.code = key
    of cmdLongOption, cmdShortOption:
      case key
      of "snippet", "s":
        result.snippets.add(value)
      of "include":
        result.includes.add(value)
      of "debug", "d":
        result.debugging = true
      of "print-result", "pr":
        result.print_result = true
      of "filter-result", "fr":
        result.filter_result = true
      of "index-name", "in":
        result.index_name = value
      of "value-name", "vn":
        result.value_name = value
      of "input-mode", "im":
        case value:
        of "csv":
          result.input_mode = ImCsv
        of "gene":
          result.input_mode = ImGene
        else:
          raise new_exception(ArgumentError, "Invalid input-mode: " & value)
      of "csv":
        result.input_mode = ImCsv
      of "gene":
        result.input_mode = ImGene
      of "line":
        result.input_mode = ImLine
      of "skip-first-line", "sf":
        result.skip_first = true
      of "skip-empty-line", "se":
        result.skip_empty = true
      of "repl-on-error":
        result.repl_on_error = true
      else:
        echo "Unknown option: ", key
        discard

    of cmdEnd:
      discard

proc eval_includes(vm: VirtualMachine, frame: Frame, options: Options) =
  if options.includes.len > 0:
    for file in options.includes:
      discard vm.eval(frame, read_file(file))

proc handle*(cmd: string, args: seq[string]): string =
  var options = parse_options(args)
  setup_logger(options.debugging)

  init_app_and_vm()
  VM.app.args = @["<eval>"].concat(args)
  var frame = VM.eval_prepare(VM.app.pkg)
  VM.app.main_module = frame.ns.module
  VM.eval_includes(frame, options)
  case options.input_mode:
  of ImCsv, ImGene, ImLine:
    var index_name = options.index_name
    var value_name = options.value_name
    var index = 0
    frame.scope.def_member(index_name.to_key, index)
    frame.scope.def_member(value_name.to_key, Nil)
    if options.input_mode == ImCsv:
      var parser: CsvParser
      parser.open(new_file_stream(stdin), "<STDIN>")
      if options.skip_first:
        parser.readHeaderRow()
      while parser.read_row():
        var val = new_gene_vec()
        for item in parser.row:
          val.vec.add(item)
        frame.scope[index_name.to_key] = index
        frame.scope[value_name.to_key] = val
        var res = VM.eval(frame, options.code)
        if options.print_result:
          if not options.filter_result or res:
            echo res.to_s
        index += 1
    elif options.input_mode == ImGene:
      var parser = new_parser()
      var stream = new_file_stream(stdin)
      parser.open(stream, "<STDIN>")
      while true:
        var val = parser.read()
        if val == nil:
          break
        frame.scope[index_name.to_key] = index
        frame.scope[value_name.to_key] = val
        var res = VM.eval(frame, options.code)
        if options.print_result:
          if not options.filter_result or res:
            echo res.to_s
        index += 1
      parser.close()
    elif options.input_mode == ImLine:
      var stream = new_file_stream(stdin)
      var val: string
      while stream.read_line(val):
        if options.skip_first and index == 0:
          index += 1
          continue
        elif options.skip_empty and val.match(re"^\s*$"):
          continue
        frame.scope[index_name.to_key] = index
        frame.scope[value_name.to_key] = val
        var res = VM.eval(frame, options.code)
        if options.print_result:
          if not options.filter_result or res:
            echo res.to_s
        index += 1
  else:
    var res = VM.eval(frame, options.code)
    if options.print_result:
      echo res.to_s

when isMainModule:
  var cmd = DEFAULT_COMMAND
  var args: seq[string] = @[]
  var status = handle(cmd, args)
  if status.len > 0:
    echo "Failed with error: " & status

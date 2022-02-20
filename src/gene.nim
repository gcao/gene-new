# See https://nim-lang.org/docs/nimprof.html
# Compiles with --profiler:on and a report will automatically be generated
# nimble build -d:release --profiler:on
# import nimprof
# setSamplingFrequency(1)

import os, parseopt, times, streams, parsecsv, re

import ./gene/types
import ./gene/map_key
import ./gene/parser
import ./gene/interpreter
import ./gene/repl

import ./gene/commands/base

let CommandMgr = CommandManager()

import "./gene/commands/run" as run_cmd; run_cmd.init(CommandMgr)

type
  InputMode* = enum
    ImDefault
    ImCsv
    ImGene
    ImLine

  Options* = ref object
    debugging*: bool
    repl*: bool
    repl_on_error*: bool
    file*: string
    eval*: string
    # snippets are wrapped like (do <snippet>) and can be accessed from anywhere
    snippets*: seq[string]
    # `include` is different from `import`.
    # `include` is like inserting content of one file in another.
    includes*: seq[string]
    args*: seq[string]
    benchmark*: bool
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
  "benchmark",
  "print-result", "pr",
  "filter-result", "fr",
  "skip-first-line", "sf",
  "skip-empty-line", "se",
  "csv",
  "gene",
  "line",
]

# When running like
# <PROGRAM> --debug test.gene 1 2 3
# test.gene is invoked with 1, 2, 3 as argument
#
# When running like
# <PROGRAM> --debug -- 1 2 3
# 1, 2, 3 are passed as argument to REPL
proc parseOptions*(): Options =
  result = Options(
    repl: true,
    index_name: "i",
    value_name: "v",
  )
  var expect_args = false
  # Stop parsing options once we see arguments
  var in_arguments = false
  for kind, key, value in getOpt(commandLineParams(), shortNoVal, longNoVal):
    case kind
    of cmdArgument:
      in_arguments = true
      if expect_args:
        result.args.add(key)
      else:
        expect_args = true
        result.repl = false
        result.file = key

    of cmdLongOption, cmdShortOption:
      if in_arguments:
        continue
      if expect_args:
        result.args.add(key)
        result.args.add(value)
      case key
      of "eval", "e":
        result.repl = false
        result.eval = value
      of "snippet", "s":
        result.snippets.add(value)
      of "include":
        result.includes.add(value)
      of "debug", "d":
        result.debugging = true
      of "benchmark":
        result.benchmark = true
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
        # of "line":
        #   result.input_mode = ImLine
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
      of "":
        expect_args = true
      else:
        echo "Unknown option: ", key
        discard

    of cmdEnd:
      discard

proc quit_with*(errorcode: int, newline = false) =
  if newline:
    echo ""
  echo "Good bye!"
  quit(errorcode)

proc eval_includes(vm: VirtualMachine, frame: Frame, options: Options) =
  if options.includes.len > 0:
    for file in options.includes:
      discard vm.eval(frame, read_file(file))

when isMainModule:
  var options = parse_options()
  setup_logger(options.debugging)

  init_app_and_vm()
  VM.repl_on_error = options.repl_on_error
  if options.repl:
    var frame = VM.eval_prepare(VM.app.pkg)
    VM.eval_includes(frame, options)
    discard repl(VM, frame, eval, false)
  elif options.eval != "":
    var frame = VM.eval_prepare(VM.app.pkg)
    VM.main_module = frame.ns.module
    VM.eval_includes(frame, options)
    case options.input_mode:
    of ImCsv, ImGene, ImLine:
      var code = options.eval
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
          var result = VM.eval(frame, code)
          if options.print_result:
            if not options.filter_result or result:
              echo result.to_s
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
          var result = VM.eval(frame, code)
          if options.print_result:
            if not options.filter_result or result:
              echo result.to_s
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
          var result = VM.eval(frame, code)
          if options.print_result:
            if not options.filter_result or result:
              echo result.to_s
          index += 1
    else:
      var result = VM.eval(frame, options.eval)
      if options.print_result:
        echo result.to_s
  else:
    var file = options.file
    let start = cpu_time()
    let result = VM.run_file(file)
    if options.print_result:
      echo result
    if options.benchmark:
      echo "Time: " & $(cpu_time() - start)

# See https://nim-lang.org/docs/nimprof.html
# Compiles with --profiler:on and a report will automatically be generated
# nimble build -d:release --profiler:on
# import nimprof
# setSamplingFrequency(1)

import times, logging, os, streams, parsecsv, re

import gene/types
import gene/map_key
import gene/parser
import gene/translators
import gene/interpreter
import gene/repl
import cmdline/option_parser

proc setup_logger(debugging: bool) =
  var console_logger = new_console_logger()
  add_handler(console_logger)
  console_logger.level_threshold = Level.lvlInfo
  if debugging:
    console_logger.level_threshold = Level.lvlDebug

proc quit_with*(errorcode: int, newline = false) =
  if newline:
    echo ""
  echo "Good bye!"
  quit(errorcode)

proc eval_includes(vm: VirtualMachine, frame: Frame, options: Options) =
  if options.includes.len > 0:
    for file in options.includes:
      discard vm.eval(frame, read_file(file))

proc main() =
  var options = parse_options()
  setup_logger(options.debugging)

  init_app_and_vm()
  VM.repl_on_error = options.repl_on_error
  if options.repl:
    var frame = VM.eval_prepare()
    VM.eval_includes(frame, options)
    discard repl(VM, frame, eval, false)
  elif options.eval != "":
    var frame = VM.eval_prepare()
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
    VM.init_package(parent_dir(file))
    let start = cpu_time()
    let result = VM.run_file(file)
    if options.print_result:
      echo result
    if options.benchmark:
      echo "Time: " & $(cpu_time() - start)

when isMainModule:
  main()

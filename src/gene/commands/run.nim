import times, logging

import gene/types
import gene/interpreter
import cmdline/option_parser

proc setup_logger(debugging: bool) =
  var console_logger = new_console_logger()
  add_handler(console_logger)
  console_logger.level_threshold = Level.lvlInfo
  if debugging:
    console_logger.level_threshold = Level.lvlDebug

proc main() =
  var options = parse_options()
  setup_logger(options.debugging)

  init_app_and_vm()
  VM.repl_on_error = options.repl_on_error

  var file = options.file
  let start = cpu_time()
  let result = VM.run_file(file)
  if options.print_result:
    echo result
  if options.benchmark:
    echo "Time: " & $(cpu_time() - start)

when isMainModule:
  main()

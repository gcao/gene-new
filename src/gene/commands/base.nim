import tables, logging

type
  CommandManager* = ref object
    data*: Table[string, Command]

  Command* = proc(cmd: string, args: seq[string]): string

proc setup_logger*(debugging: bool) =
  var console_logger = new_console_logger()
  add_handler(console_logger)
  console_logger.level_threshold = Level.lvlInfo
  if debugging:
    console_logger.level_threshold = Level.lvlDebug

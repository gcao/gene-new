import os, posix, strutils

# import ../h3rald/nimline
import nimline

import ./types
import ./parser

type
  KeyboardInterrupt = object of CatchableError

  Eval = proc(self: VirtualMachine, frame: Frame, code: string): Value

# Ctrl-C to cancel current input
# https://rosettacode.org/wiki/Handle_a_signal#Nim
proc handler() {.noconv.} =
  var nmask, omask: Sigset
  discard sigemptyset(nmask)
  discard sigemptyset(omask)
  discard sigaddset(nmask, SIGINT)
  if sigprocmask(SIG_UNBLOCK, nmask, omask) == -1:
    raiseOSError(osLastError())
  raise new_exception(KeyboardInterrupt, "Keyboard Interrupt")

proc prompt(message: string): string =
  return "\u001B[36m" & message & "\u001B[0m"

# https://stackoverflow.com/questions/5762491/how-to-print-color-in-console-using-system-out-println
# https://en.wikipedia.org/wiki/ANSI_escape_code
proc error(message: string): string =
  return "\u001B[31m" & message & "\u001B[0m"

method show_exception(ex: ref system.Exception) =
  var s = ex.get_stack_trace()
  s.strip_line_end()
  echo s
  echo error("$#: $#" % [$ex.name, $ex.msg])

proc show_result(v: Value) =
  if v == nil:
    stdout.write_line("nil")
  elif v.kind != VkPlaceholder:
    stdout.write_line(v)

proc repl*(self: VirtualMachine, frame: Frame, eval: Eval, return_value: bool): Value =
  try:
    set_control_c_hook(handler)
    echo "Welcome to interactive Gene!"
    echo "Note: press Ctrl-D or type exit to exit."

    var ed = init_editor(history_file = get_env("HOME") & "/.gene_history")
    ed.completion_callback = proc(ed: LineEditor): seq[string] =
      @["(var", "(import", "(class", "(mixin", "(method", "(print", "(println", "(for", "(if", "elif", "else",
        "($env", "($tap",
      ]

    var input = ""
    while true:
      try:
        let line = ed.read_line(prompt("Gene> "))

        if input.len > 0:
          input &= "\n" & line
        else:
          input = line

        case input
        of "":
          continue
        of "help":
          todo()
          continue
        of "exit", "quit":
          quit(0)
        else:
          discard

        result = eval(self, frame, input)
        show_result(result)

        # Reset input
        input = ""

      except EOFError:
        echo()
        # Rewind to beginning of file
        stdin.set_file_pos(0)
        break
      except ParseError as e:
        # Incomplete expression
        if e.msg.starts_with("EOF"):
          continue
        else:
          input = ""
          show_exception(e)
      except KeyboardInterrupt:
        echo()
        input = ""
      except Return as r:
        result = r.val
        stdout.write_line(result)
        break
      except system.Exception as e:
        result = Nil
        input = ""
        show_exception(e)

    if return_value:
      if result == nil:
        result = Nil
    else:
      return Nil
  finally:
    unset_control_c_hook()

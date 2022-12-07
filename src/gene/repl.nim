import strutils, os, posix

import ./types
import ./parser

# TODO: readline support for REPL
# https://stackoverflow.com/questions/61079605/how-to-write-a-text-prompt-in-nim-that-has-readline-style-line-editing
# https://github.com/jangko/nim-noise
#
# Ctrl-C to cancel current input

type
  KeyboardInterrupt = object of CatchableError

  Eval = proc(self: VirtualMachine, frame: Frame, code: string): Value

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

proc show_result(v: Value) =
  if v == nil:
    stdout.write_line("nil")
  elif v.kind != VkPlaceholder:
    stdout.write_line(v)

proc repl*(self: VirtualMachine, frame: Frame, eval: Eval, return_value: bool): Value =
  echo "Welcome to interactive Gene!"
  echo "Note: press Ctrl-D to exit."

  set_control_c_hook(handler)
  try:
    var input = ""
    while true:
      stdout.write(prompt("Gene> "))
      try:
        input = input & stdin.read_line()
        input = input.strip()
        case input:
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
      except KeyboardInterrupt:
        echo()
        input = ""
      except Return as r:
        result = r.val
        stdout.write_line(result)
        break
      except system.Exception as e:
        result = Value(kind: VkNil)
        input = ""
        var s = e.get_stack_trace()
        s.strip_line_end()
        echo s
        echo error("$#: $#" % [$e.name, $e.msg])
  finally:
    unset_control_c_hook()
  if return_value:
    if result == nil:
      result = Value(kind: VkNil)
  else:
    return Value(kind: VkNil)

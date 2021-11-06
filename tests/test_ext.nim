import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

# test_extension "tests/libextension", "test", proc(r: NativeFn) =
#   var props = OrderedTable[string, Value]()
#   var data = @[1, 2]
#   check r(props, data) == 3

proc test_extension*(code: string, result: Value) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    init_all()
    discard VM.eval("(import_native from \"tests/libextension\")")
    check VM.eval(code) == result

test_extension """
  (test 1)
""", 1

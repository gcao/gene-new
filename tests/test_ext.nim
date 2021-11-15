import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

proc test_extension(code: string, result: Value) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    discard VM.eval("(import_native from \"tests/libextension\")")
    check VM.eval(code) == result

suite "Extension":
  init_all()

  test_extension """
    (test 1)
  """, 1

  test_extension """
    MyClass/.name
  """, "MyClass"

  test_extension """
    ((test (throw "error")) .message)
  """, "error"

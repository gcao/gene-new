import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

proc test_extension(code: string, result: Value) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    check VM.eval(code) == result

suite "Extension":
  init_all()
  discard VM.eval("(import_native from \"tests/libextension\")")

  test_extension """
    (test 1)
  """, 1

  test_extension """
    (test_i (new_test 1 "s"))
  """, 1

  test_extension """
    TestClass/.name
  """, "TestClass"

  test_extension """
    ((test (throw "error")) .message)
  """, "error"

import unittest

import gene/types
import gene/interpreter

import ./helpers

proc test_extension(code: string, result: Value) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    check VM.eval(code) == result

suite "Extension":
  init_all()
  discard VM.eval("""
    (import_native from "tests/libextension")
    (import_native new_extension2 extension2_name from "tests/libextension2")
    (var global/new_extension2 new_extension2)
    (var global/extension2_name extension2_name)
  """)

  test_extension """
    (test 1)
  """, 1

  test_extension """
    (test (extension2_name (new_extension2 "x")))
  """, "x"

  test_extension """
    (get_i (new_extension 1 "s"))
  """, 1

  test_extension """
    (((new_extension 1 "s") .class) .name)
  """, "Extension"

  test_extension """
    ((new_extension 1 "s") .i)
  """, 1

  test_extension """
    ((new Extension 1 "s") .i)
  """, 1

  test_extension """
    Extension/.name
  """, "Extension"

  test_extension """
    (try
      (test (throw "error"))
    catch _
      $ex/.message
    )
  """, "error"

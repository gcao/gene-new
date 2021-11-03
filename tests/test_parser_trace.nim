import unittest

import gene/types
import gene/parser

import ./helpers

proc test_tracing*(code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    var parser = new_parser()
    parser.options.trace = true
    callback parser.read(code)

test_tracing "nil", proc(r: Value) =
  check r.trace.start_line == 0
  check r.trace.start_col == 0
  check r.trace.end_line == 0
  check r.trace.end_col == 2

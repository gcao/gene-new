import unittest, strutils, tables

import gene/map_key
import gene/types
import gene/parser
# import gene/normalizers
import gene/interpreter
# import gene/interpreter_extras

# Uncomment below lines to see logs
# import logging
# addHandler(newConsoleLogger())

proc init_all*() =
  init_app_and_vm()

# This is added to make it easier to write tests
converter str_to_key*(s: string): MapKey {.inline.} =
  if KeyMapping.has_key(s):
    result = KeyMapping[s]
  else:
    result = add_key(s)

converter key_to_s*(self: MapKey): string {.inline.} =
  result = Keys[cast[int](self)]

converter seq_to_gene*(self: seq[int]): seq[Value] =
  for item in self:
    result.add(item)

converter seq_to_gene*(self: seq[string]): seq[Value] =
  for item in self:
    result.add(item)

proc cleanup*(code: string): string =
  result = code
  result.stripLineEnd
  if result.contains("\n"):
    result = "\n" & result

proc test_parser*(code: string, result: Value) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    check read(code) == result

proc test_parser*(code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    callback read(code)

proc test_parser_error*(code: string) =
  var code = cleanup(code)
  test "Parser error expected: " & code:
    try:
      discard read(code)
    except ParseError:
      discard

proc test_read_all*(code: string, result: seq[Value]) =
  var code = cleanup(code)
  test "Parser / read_all: " & code:
    check read_all(code) == result

proc test_read_all*(code: string, callback: proc(result: seq[Value])) =
  var code = cleanup(code)
  test "Parser / read_all: " & code:
    callback read_all(code)

# proc test_normalize*(code: string, r: Value) =
#   var code = cleanup(code)
#   test "normalize: " & code:
#     var parsed = read(code)
#     parsed.normalize
#     check parsed == r

# proc test_normalize*(code: string, r: string) =
#   test_normalize(code, read(r))

proc test_interpreter*(code: string, result: Value) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    init_all()
    check VM.eval(code) == result

proc test_interpreter*(code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    init_all()
    callback VM.eval(code)

proc test_parse_document*(code: string, callback: proc(result: Document)) =
  var code = cleanup(code)
  test "Parse document: " & code:
    callback read_document(code)

# proc test_core*(code: string) =
#   var code = cleanup(code)
#   test "Interpreter / eval: " & code:
#     init_all()
#     VM.load_core_module()
#     VM.load_gene_module()
#     VM.load_genex_module()
#     discard VM.eval(code)

# proc test_core*(code: string, result: Value) =
#   var code = cleanup(code)
#   test "Interpreter / eval: " & code:
#     init_all()
#     VM.load_core_module()
#     VM.load_gene_module()
#     VM.load_genex_module()
#     check VM.eval(code) == result

# proc test_core*(code: string, callback: proc(result: Value)) =
#   var code = cleanup(code)
#   test "Interpreter / eval: " & code:
#     init_all()
#     VM.load_core_module()
#     VM.load_gene_module()
#     VM.load_genex_module()
#     callback VM.eval(code)

# proc test_arg_matching*(pattern: string, input: string, callback: proc(result: MatchResult)) =
#   var pattern = cleanup(pattern)
#   var input = cleanup(input)
#   test "Pattern Matching: \n" & pattern & "\n" & input:
#     var p = read(pattern)
#     var i = read(input)
#     var m = new_arg_matcher()
#     m.parse(p)
#     var result = m.match(i)
#     callback(result)

# proc test_match*(pattern: string, input: string, callback: proc(result: MatchResult)) =
#   var pattern = cleanup(pattern)
#   var input = cleanup(input)
#   test "Pattern Matching: \n" & pattern & "\n" & input:
#     var p = read(pattern)
#     var i = read(input)
#     var m = new_match_matcher()
#     m.parse(p)
#     var result = m.match(i)
#     callback(result)

# proc test_import_matcher*(code: string, callback: proc(result: ImportMatcherRoot)) =
#   var code = cleanup(code)
#   test "Import: " & code:
#     var v = read(code)
#     var m = new_import_matcher(v)
#     callback m

# proc test_args*(schema, input: string, callback: proc(r: ArgMatchingResult)) =
#   var schema = cleanup(schema)
#   var input = cleanup(input)
#   test schema & "\n" & input:
#     var m = new_cmd_args_matcher()
#     m.parse(read(schema))
#     var r = m.match(input)
#     callback r

# proc test_file*(file: string) =
#   test "Tests " & file & ":":
#     init_all()
#     VM.load_core_module()
#     VM.load_gene_module()
#     VM.load_genex_module()
#     discard VM.eval(read_file(file))

# proc test_extension*(path: string, name: string, callback: proc(r: NativeFn)) =
#   test "Interpreter / eval - extension: " & path & "." & name:
#     let lib = load_lib("tests/lib" & path & ".dylib")
#     if lib == nil:
#       skip()
#     else:
#       let ext = lib.sym_addr(name)
#       if ext != nil:
#         callback cast[NativeFn](ext)

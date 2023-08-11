import unittest, options, tables, unicode, times, nre

import gene/types
import gene/geni_parser as parser

import ./helpers

proc test_parser*(code: string, result: Value) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    check read(code) == result

proc test_parser*(code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    var parser = new_parser()
    callback parser.read(code)

proc test_parser_error*(code: string) =
  var code = cleanup(code)
  test "Parser error expected: " & code:
    try:
      discard read(code)
      fail()
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

proc test_parse_document*(code: string, callback: proc(result: Document)) =
  var code = cleanup(code)
  test "Parse document: " & code:
    callback read_document(code)

test_parser "1", new_gene_gene(1)
test_parser """
  1
""", new_gene_gene(1)
test_parser "= 1", 1
test_parser "= =", new_gene_symbol("=")
# test_read_all """
#   =
#     1
#     2
# """, @[new_gene_int(1), new_gene_int(2)]

test_parser """
  = []
""", new_gene_vec()

test_parser """
  if cond
    = 1
    = 2
""", proc(r: Value) =
  check r.kind == VkGene
  check r.gene_type == new_gene_symbol("if")
  check r.gene_children[0] == new_gene_symbol("cond")
  check r.gene_children[1] == 1
  check r.gene_children[2] == 2

# () should be on the same line because this looks bad ?!
# a (if cond
#   do_this
# else
#   do_that
# )
# What about #"...#(...)..."?
# It might be hard to put #(...) on the same line.
# test_parser_error """
#   a (b
#     c
#   )
# """

test_parser """
  if cond
    = 1
  else
    = 2
""", proc(r: Value) =
  check r.kind == VkGene
  check r.gene_type == new_gene_symbol("if")
  check r.gene_children[0] == new_gene_symbol("cond")
  check r.gene_children[1] == 1
  check r.gene_children[2] == new_gene_symbol("else")
  check r.gene_children[3] == 2

test_parser """
  = [
    = 1
  ]
""", new_gene_vec(1)

# test_parser """
#   #Array
#     = 1
# """, new_gene_vec(new_gene_gene(1))

# test_parser """
#   = {
#     ^a 1
#   }
# """, {"a": new_gene_int(1)}.toTable

# test_parser """
#   #Map
#     ^a 1
# """, {"a": new_gene_int(1)}.toTable

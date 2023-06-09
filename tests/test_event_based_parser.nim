import unittest, options, tables, unicode, times, nre

import gene/types
import gene/event_based_parser as parser

import ./helpers

proc test_parser*(code: string, result: Value) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    check read(code) == result

test_parser "nil", Value(kind: VkNil)
test_parser "true", true
test_parser "false", false

test_parser "10", 10
test_parser "-1", -1
test_parser "10e10", 10e10
test_parser "+5.0E5", +5.0E5

# test_parser "\\\\", '\\'
# test_parser "\\s", 's'
# test_parser "\\space", ' '
# test_parser "\\t", 't'
# test_parser "\\tab", '\t'
# test_parser "\\n", 'n'
# test_parser "\\newline", '\n'
# test_parser "\\r", 'r'
# test_parser "\\return", '\r'
# test_parser "\\f", 'f'
# test_parser "\\formfeed", '\f'
# test_parser "\\b", 'b'
# test_parser "\\backspace", '\b'
# test_parser "\\中", "中".runeAt(0)

# test_parser "\\\"nil\"", new_gene_symbol("nil")
# test_parser "\\\"true\"", new_gene_symbol("true")
# test_parser "\\\"false\"", new_gene_symbol("false")
# test_parser "\\'nil'", new_gene_symbol("nil")

test_parser "\"test\"", "test"
test_parser ",\"test\",", "test"
test_parser "'test'", "test"
test_parser ",'test',", "test"

test_parser "a", new_gene_symbol("a")
test_parser "A", new_gene_symbol("A")
test_parser "+a", new_gene_symbol("+a")
# test_parser "#a", new_gene_symbol("#a")
test_parser "a#b", new_gene_symbol("a#b")
test_parser "a:b", new_gene_symbol("a:b")
test_parser "a\\ b", new_gene_symbol("a b")
test_parser "a\\/b", new_gene_symbol("a/b")
test_parser "n/A", new_gene_complex_symbol(@["n", "A"])
test_parser "n\\/A/B", new_gene_complex_symbol(@["n/A", "B"])
test_parser "n/m/A", new_gene_complex_symbol(@["n", "m", "A"])
test_parser "/A", new_gene_complex_symbol(@["", "A"])
test_parser "^a", new_gene_symbol("^a")
test_parser "symbol-👋", new_gene_symbol("symbol-👋")
test_parser "+foo+", new_gene_symbol("+foo+")

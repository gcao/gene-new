# To run these tests, simply execute `nimble test` or `nim c -r tests/test_parser.nim`

import unittest, options, tables, unicode, times, nre

import gene/types

import ./helpers

# #B... Bin
# #X... Hex
# (#Base64 ...)  Base64

# Parser options:
# A map of name->stack is used to store parser options
# A cache of computed options are stored, and refreshed whenever any of below commands is found.
# (#Set name value)
# (#Unset name...) - will clear non-pushed top value of the stack
# (#Reset name...) - will clear all non-pushed values of the stack
# (#Push name value)
# Set vs Push:
# Options are applicable to end of document or until it's changed by further Set/Unset/....
# Options are applicable to gene/array/map and will be removed automatically
# Push is recommended over Set

# Usecases:
# (#Set x 1) (#Get x) -> 1
# [(#Set x 1)] (#Get x) -> 1

# (#Push x 1) (#Get x) -> 1
# [(#Push x 1)] (#Get x) -> nil

# [(#Push x 1) (#Set x 2)] (#Get x) -> 2
# ...

test_parser "nil", Nil
test_parser "true", true
test_parser "false", false

test_parser "10", 10
test_parser "-1", -1
test_parser "10e10", 10e10
test_parser "+5.0E5", +5.0E5

# Support simple numbers with unit (e.g. 3px) and complex numbers with units (e.g. 1m30s)
# Support custom units (e.g. 1x) - a mapping should be provided to the parser or added to the document
#   e.g. (#Unit x 100) -> 1x = 100 default unit
# Standard unit can be overwritten, e.g. (#Unit m 60) -> 1m = 60
# Mixing units of different type is supported (e.g. 1km2s). The parser won't validate unit type.
# See https://www.britannica.com/science/International-System-of-Units
# Common units to support (but not limited to these):
# They can be converted to default unit for the type of measurement

# km, kilometer
# m, meter - default
# cm, centimeter
# mm, millimeter
# um, micrometer
# nm, nanometer

# y, year
# mon, month
# d, day
# h, hour
# min, minute
# s, sec, second - default
# ms, millisecond
# us, microsecond
# ns, nanosecond

# kg, kilogram
# g, gram - default
# mg, milligram
# lb, pound

# px, pixel - default

# %: 1% equals to 0.01 (we can imagine 100% is the default)

# test_parser "10m", 600
# test_parser "0.5m", 30
# test_parser "10m30s", 630
# test_parser "30s10m", 630  # The order does not matter

test_parser "\\\\", '\\'
test_parser "\\s", 's'
test_parser "\\space", ' '
test_parser "\\t", 't'
test_parser "\\tab", '\t'
test_parser "\\n", 'n'
test_parser "\\newline", '\n'
test_parser "\\r", 'r'
test_parser "\\return", '\r'
test_parser "\\f", 'f'
test_parser "\\formfeed", '\f'
test_parser "\\b", 'b'
test_parser "\\backspace", '\b'
test_parser "\\中", "中".runeAt(0)

test_parser "\\\"nil\"", new_gene_symbol("nil")
test_parser "\\\"true\"", new_gene_symbol("true")
test_parser "\\\"false\"", new_gene_symbol("false")
test_parser "\\'nil'", new_gene_symbol("nil")

test_parser "\"test\"", "test"
test_parser ",\"test\",", "test"
test_parser "'test'", "test"
test_parser ",'test',", "test"

test_parser "a", new_gene_symbol("a")
test_parser "A", new_gene_symbol("A")
test_parser "+a", new_gene_symbol("+a")
test_parser "#a", new_gene_symbol("#a")
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

test_parser "#/b/", proc(r: Value) =
  check r.kind == VkRegex
  check "ab".find(r.regex).get().captures[-1] == "b"
  check "AB".find(r.regex).is_none()

test_parser "#/(a|b)/", proc(r: Value) =
  check r.kind == VkRegex
  check "ab".find(r.regex).get().captures[-1] == "a"
  check "AB".find(r.regex).is_none()

test_parser "#/a\\/b/", proc(r: Value) =
  check r.kind == VkRegex
  check "a/b".find(r.regex).get().captures[-1] == "a/b"

# i: ignore case
# m: multi-line mode, ^ and $ matches beginning and end of each line
test_parser "#/b/i", proc(r: Value) =
  check r.kind == VkRegex
  check "ab".find(r.regex).get().captures[-1] == "b"
  check "AB".find(r.regex).get().captures[-1] == "B"

test_parser "2020-12-02", new_gene_date(2020, 12, 02)
test_parser "2020-12-02T10:11:12Z",
  new_gene_datetime(init_date_time(02, cast[Month](12), 2020, 10, 11, 12, utc()))
test_parser "10:11:12", new_gene_time(10, 11, 12)

test_parser "{}", OrderedTable[string, Value]()
test_parser "{^a 1}", {"a": new_gene_int(1)}.toOrderedTable

test_parser "[]", new_gene_vec()
test_parser "[,]", new_gene_vec()
test_parser "[1 2]", new_gene_vec(new_gene_int(1), new_gene_int(2))
test_parser "[1, 2]", new_gene_vec(new_gene_int(1), new_gene_int(2))

test_parser "#[]", new_gene_set()
test_parser "#[1 2]", new_gene_set(new_gene_int(1), new_gene_int(2))

test_parser ",a", new_gene_symbol("a")
test_parser "a,", new_gene_symbol("a")

test_parser "1 2 3", 1

test_parser "()", proc(r: Value) =
  check r.gene_type == nil
  check r.gene_props.len == 0
  check r.gene_children.len == 0

test_parser "(())", proc(r: Value) =
  check r.kind == VkGene
  check r.gene_children.len == 0
  check r.gene_type.kind == VkGene
  check r.gene_type.gene_children.len == 0

test_parser "(1 2 3)", proc(r: Value) =
  check r.gene_type == 1
  check r.gene_children == @[2, 3]

test_parser """
  (_ 1 "test")
""", proc(r: Value) =
  check r.gene_children[0] == 1
  check r.gene_children[1] == "test"

test_parser "(1 ^a 2 3 4)", proc(r: Value) =
  check r.gene_type == 1
  check r.gene_props == {"a": new_gene_int(2)}.toOrderedTable
  check r.gene_children == @[3, 4]

test_parser "(1 2 ^a 3 4)", proc(r: Value) =
  check r.gene_type == 1
  check r.gene_props == {"a": new_gene_int(3)}.toOrderedTable
  check r.gene_children == @[2, 4]

test_parser "(1 ^^a 2 3)", proc(r: Value) =
  check r.gene_type == 1
  check r.gene_props == {"a": True}.toOrderedTable
  check r.gene_children == @[2, 3]

test_parser "(1 ^!a 2 3)", proc(r: Value) =
  check r.gene_type == 1
  check r.gene_props == {"a": False}.toOrderedTable
  check r.gene_children == @[2, 3]

test_parser "{^^x ^!y ^^z}", proc(r: Value) =
  check r.kind == VkMap
  check r.map == {"x": True, "y": False, "z": True}.toOrderedTable

test_parser ":foo", proc(r: Value) =
  check r.kind == VkQuote
  check r.quote == new_gene_symbol("foo")

test_parser "%foo", proc(r: Value) =
  check r.kind == VkUnquote
  check r.unquote == new_gene_symbol("foo")
  check r.unquote_discard == false

test_parser "%_foo", proc(r: Value) =
  check r.kind == VkUnquote
  check r.unquote == new_gene_symbol("foo")
  check r.unquote_discard == true

# TODO: %_ is not allowed on gene type and property value
# (%_foo)         should throw error
# (a ^name %_foo) should throw error
# {^name %_foo}   should throw error

# test_parser "#_ [foo bar]", proc(r: Value) =
#   check r == nil

test_parser "1/2", proc(r: Value) =
  check r.kind == VkRatio
  check r.ratio_num == BiggestInt(1)
  check r.ratio_denom == BiggestInt(2)

test_parser "{^ratio -1/2}", proc(r: Value) =
  check r.kind == VkMap
  check r.map["ratio"] == new_gene_ratio(-1, 2)

test_parser_error """
  # Gene properties should not be mixed with children like below
  (a ^b b c ^d d) # b & d are properties but are separated by c
"""

test_parser_error "{^ratio 1/-2}"

# Support decorator from the parser. It can appear anywhere except property names.
# Pros:
#   Easier to write
# Cons:
#   Harder to read ?!
#
# #@f a       = (f a)
# (#@f a)     = ((f a))
# (#@f #@g a) = ((f (g a)))
# #@(f a) b   = (((f a) b))
# {^p #@f a}  = {^p (f a)}

test_parser """
  #@f a
""", proc(r: Value) =
  check r.kind == VkGene
  check r.gene_type.symbol == "f"
  check r.gene_children[0].symbol == "a"

test_parser """
  #@f #@g a
""", proc(r: Value) =
  check r.kind == VkGene
  check r.gene_type.symbol == "f"
  check r.gene_children[0].kind == VkGene
  check r.gene_children[0].gene_type.symbol == "g"
  check r.gene_children[0].gene_children[0].symbol == "a"

# test_parser """
#   #*f
# """, proc(r: Value) =
#   check r.kind == VkGene
#   check r.gene_type.symbol == "f"

test_parser """
  {^p #@f a}
""", proc(r: Value) =
  check r.map["p"].kind == VkGene
  check r.map["p"].gene_type.symbol == "f"
  check r.map["p"].gene_children[0].symbol == "a"

test_read_all """
  1 # comment
  2
""", proc(r: seq[Value]) =
  check r[0] == 1
  check r[1] == 2

test_read_all """
  1 ##comment
  2
""", proc(r: seq[Value]) =
  check r[0] == 1
  check r[1] == 2

test_read_all "a,b", proc(r: seq[Value]) =
  check r[0] == new_gene_symbol("a")
  check r[1] == new_gene_symbol("b")

test_read_all "1 2", @[new_gene_int(1), new_gene_int(2)]

test_parser """
  [
    1 # test
  ]
""", @[1]

test_parser """
  #
  # comment
  #
  1
  #
""", 1

test_parser "[a/[1 2]]", proc(r: Value) =
  check r.vec[0].csymbol[0] == "a"
  check r.vec[0].csymbol[1] == ""
  check r.vec[1].vec[0] == 1
  check r.vec[1].vec[1] == 2

test_parser """
  #< comment ># 1
""", 1

test_parser """
  #< #<< comment >># ># 1
""", 1

test_parser """
  #<
  comment
  #># 1
""", 1

test_parser """
  #<
  comment
  #>## 1
  2
""", 2

test_parser """
  #<
  #<<
  comment
  #>>#
  #># 1
""", 1

test_parse_document """
  ^name "Test document"
  ^version "0.1.0"
""", proc(r: Document) =
  check r.props["name"] == "Test document"
  check r.props["version"] == "0.1.0"
  check r.children.len == 0

test_parse_document """
  ^name "Test document"
  1 2
""", proc(r: Document) =
  check r.props["name"] == "Test document"
  check r.children == @[1, 2]

test_parser "\"\"\"a\"\"\"", "a"
# Trim whitespaces and new line after opening """
# E.g. """  \na""" => "a"
test_parser "\"\"\"  \na\"\"\"", "a"
# Trim whitespaces before closing """
# E.g. """a\n   """ => "a\n"
test_parser "\"\"\"a\n   \"\"\"", "a\n"

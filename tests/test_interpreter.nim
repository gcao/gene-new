import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

test_interpreter "nil", Nil
test_interpreter "1", 1
test_interpreter "true", true
test_interpreter "false", false
test_interpreter "\"string\"", "string"
test_interpreter ":a", new_gene_symbol("a")

test_interpreter "1 2 3", 3

test_interpreter "[]", new_gene_vec()
test_interpreter "[1 2]", new_gene_vec(1, 2)

test_interpreter "{}", OrderedTable[string, Value]()
test_interpreter "{^a 1}", {"a": new_gene_int(1)}.toOrderedTable

test_interpreter "(:test 1 2)", proc(r: Value) =
  check r.gene_type == new_gene_symbol("test")
  check r.gene_data[0] == 1
  check r.gene_data[1] == 2

# test_interpreter """
#   (var a 1)
#   :(test %a 2)
# """, proc(r: Value) =
#   check r.gene_type == new_gene_symbol("test")
#   check r.gene_data[0] == 1
#   check r.gene_data[1] == 2

# test_interpreter """
#   :(test
#     %_(var a 1)
#     %a
#     2
#   )
# """, proc(r: Value) =
#   check r.gene_type == new_gene_symbol("test")
#   check r.gene_data[0] == 1
#   check r.gene_data[1] == 2

# # test_interpreter """
# #   (var a [1 2])
# #   :(test
# #     %a...
# #     3
# #   )
# # """, proc(r: Value) =
# #   check r.gene_type == new_gene_symbol("test")
# #   check r.gene_data[0] == 1
# #   check r.gene_data[1] == 2
# #   check r.gene_data[2] == 3

# # TODO: nested quote/unquote, need more thoughts before implementing
# # test_interpreter """
# #   (var a 1)
# #   ::(test %a 2)
# # """, proc(r: Value) =
# #   check r == read(":(test %a 2)")

# # test_interpreter """
# #   (var a 1)
# #   ::(test %%a 2)
# # """, proc(r: Value) =
# #   check r == read(":(test 1 2)")

# test_interpreter "(range 0 100)", proc(r: Value) =
#   check r.range_start == 0
#   check r.range_end == 100

test_interpreter "(1 + 2)", 3
test_interpreter "(1 - 2)", -1

test_interpreter "(1 == 1)", true
test_interpreter "(1 == 2)", false
test_interpreter "(1 < 0)", false
test_interpreter "(1 < 1)", false
test_interpreter "(1 < 2)", true
test_interpreter "(1 <= 0)", false
test_interpreter "(1 <= 1)", true
test_interpreter "(1 <= 2)", true

test_interpreter "(true && false)", false
test_interpreter "(true && true)", true
test_interpreter "(true || false)", true
test_interpreter "(false && false)", false

test_interpreter "(var a 1) a", 1
# test_interpreter "(var a 1) (a = 2) a", 2
# test_interpreter "(var a) (a = 2) a", 2

# test_interpreter "(var /a 1) a", 1
# test_interpreter "(var /a 1) /a", 1

# test_interpreter """
#   (var a 1)
#   (var b 2)
#   [a b]
# """, proc(r: Value) =
#   check r.vec[0] == 1
#   check r.vec[1] == 2

# test_interpreter """
#   (var a 1)
#   (var b 2)
#   {^a a ^b b}
# """, proc(r: Value) =
#   check r.map["a"] == 1
#   check r.map["b"] == 2

# test_interpreter """
#   (var a 1)
#   (var b 2)
#   (:test ^a a b)
# """, proc(r: Value) =
#   check r.gene_props["a"] == 1
#   check r.gene_data[0] == 2

# test_interpreter "(if true 1)", 1
# test_interpreter "(if not false 1)", 1
# test_interpreter "(if false 1 else 2)", 2
# test_interpreter """
#   (if false
#     1
#   elif true
#     2
#   else
#     3
#   )
# """, 2

# test_interpreter "(do 1 2)", 2

# test_interpreter """
#   (do ^self 1
#     self
#   )
# """, 1

# test_interpreter """
#   (var i 0)
#   (loop
#     (i += 1)
#     (break)
#   )
#   i
# """, 1

# test_interpreter """
#   (var i 0)
#   (loop
#     (i += 1)
#     (break i)
#   )
# """, 1

# test_interpreter """
#   (var i 0)
#   (loop
#     (i += 1)
#     (if (i < 5)
#       (continue)
#     else
#       (break)
#     )
#     (i = 10000)  # should not reach here
#   )
#   i
# """, 5

# test_interpreter """
#   (var i 0)
#   (while (i < 3)
#     (i += 1)
#   )
#   i
# """, 3

# test_interpreter """
#   (var i 0)
#   (while true
#     (i += 1)
#     (if (i < 3)
#       (continue)
#     else
#       (break)
#     )
#     (i = 10000)  # should not reach here
#   )
#   i
# """, 3

# test_interpreter """
#   (var sum 0)
#   (for i in (range 0 4)
#     (sum += i)
#   )
#   sum
# """, 6 # 0 + 1 + 2 + 3

# test_interpreter """
#   (var sum 0)
#   (for i in (range 0 4)
#     (sum += i)
#     (if (i < 2)
#       (continue)
#     else
#       (break)
#     )
#     (sum = 10000)  # should not reach here
#   )
#   sum
# """, 3 # 0 + 1 + 2

# test_interpreter """
#   (var sum 0)
#   (for i in [1 2 3]
#     (sum += i)
#   )
#   sum
# """, 6

# test_interpreter """
#   (var sum 0)
#   (for [k v] in {^a 1 ^b 2}
#     (sum += v)
#   )
#   sum
# """, 3

# test_interpreter """
#   (var sum 0)
#   (for [k _] in [1 2 3]
#     (sum += k)
#   )
#   sum
# """, 3

# test_interpreter "self", GeneNil

# # test_interpreter """
# #   (call_native "str_size" "test")
# # """, 4

# test_interpreter """
#   (var a 1)
#   (var b 2)
#   (eval :a :b)
# """, 2

# test_interpreter """
#   (eval ^self 1 self)
# """, 1

# # TODO: (caller_eval ...) = (eval ^context caller_context ...)

# test_interpreter """
#   (var a (:test 1))
#   ($set a 0 2)
#   ($get a 0)
# """, 2

# test_interpreter """
#   (var i 1) # first i
#   (fn f _
#     i       # reference to first i
#   )
#   (var i 2) # second i
#   (f)
# """, 1

# test_interpreter """
#   (var a [2 3])
#   [1 a... 4]
# """, @[new_gene_int(1), new_gene_int(2), new_gene_int(3), new_gene_int(4)]

# test_interpreter """
#   [1 (... [2 3]) 4]
# """, @[new_gene_int(1), new_gene_int(2), new_gene_int(3), new_gene_int(4)]

# test_interpreter """
#   (enum A first second)
#   A
# """, proc(r: Value) =
#   var e = r.internal.enum
#   check e.name == "A"
#   check e.members.len == 2
#   check e.members["first"].name == "first"
#   check e.members["first"].value == 0
#   check e.members["second"].name == "second"
#   check e.members["second"].value == 1

# test_interpreter """
#   (enum A
#     first = 1
#     second      # value will be 2
#   )
#   A/second
# """, proc(r: Value) =
#   var m = r.internal.enum_member
#   check m.parent.name == "A"
#   check m.name == "second"
#   check m.value == 2

# test_interpreter """
#   (enum A first second)
#   A/second/parent
# """, proc(r: Value) =
#   var e = r.internal.enum
#   check e.name == "A"

# test_interpreter """
#   (enum A first second)
#   A/second/name
# """, "second"

# test_interpreter """
#   (enum A first second)
#   A/second/value
# """, 1

# test "Interpreter / eval: native function (test)":
#   init_all()
#   VM.app.ns["test"] = proc(props: OrderedTable[MapKey, Value], data: seq[Value]): Value {.nimcall.} =
#     1
#   var code = cleanup """
#     (test)
#   """
#   check VM.eval(code) == 1

# test "Interpreter / eval: native function (test 1 2)":
#   init_all()
#   VM.app.ns["test"] = proc(props: OrderedTable[MapKey, Value], data: seq[Value]): Value {.nimcall.} =
#     data[0].int + data[1].int
#   var code = cleanup """
#     (test 1 2)
#   """
#   check VM.eval(code) == 3

# test_interpreter """
#   ($def_ns_member "a" 1)
#   a
# """, 1

# test_interpreter """
#   ($def_member "a" 1)
#   a
# """, 1

# test_interpreter """
#   (eval ($parse "1"))
# """, 1

# test_interpreter """
#   ($include "tests/fixtures/include_example.gene")
#   a
# """, 100

# test_interpreter """
#   [
#     ($include "tests/fixtures/include_example.gene")
#   ]
# """, @[new_gene_int(1), new_gene_int(2), new_gene_int(3)]

# test_interpreter """
#   $app
# """, proc(r: Value) =
#   check r.internal.app.ns.name == "global"

# # HOT RELOAD
# # Module must be marked as reloadable first
# # We need symbol table per module
# # Symbols are referenced by names/keys
# # Should work for imported symbols, e.g. (import a from "a")
# # Should work for aliases when a symbol is imported, e.g. (import a as b from "a")
# # Should not reload `b` if `b` is defined like (import a from "a") (var b a)
# # Should work for child members of imported symbols, e.g. (import a from "a") a/b

# # Reload occurs in the same thread at controllable interval.
# # https://github.com/paul-nameless/nim-fswatch
# # https://github.com/FedericoCeratto/nim-fswatch

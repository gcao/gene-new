import unittest, tables

import gene/types

import ./helpers

# Keywords:
# nil, true, false, _, not, NaN
# if, then, elif, else
# not, !
# and, or, xor, xand, &&, ||, ||*(xor: a && !b + !a && b), &&* (xand: a && b + !a && !b)
# var
# do
# loop, while, repeat, next, break
# for, in
# module, import, from, of, as
# ns
# class, mixin, method, new, super
# cast
# self
# fn, fnx, fnxx, return
# macro
# match
# enum
# try, catch, ensure, throw
# async, await
# global
# gene, genex
# #...
# $... (e.g. $app, $pkg, $ns, $module, $args)
# +, -, *, /, =, ...
# ==, !=, > >= < <=
# ->, =>

test_interpreter "nil", Nil
test_interpreter "1", 1
test_interpreter "true", true
test_interpreter "false", false
test_interpreter "_", Placeholder
test_interpreter "\"string\"", "string"
test_interpreter ":a", new_gene_symbol("a")

test_interpreter "1 2 3", 3

test_interpreter "[]", new_gene_vec()
test_interpreter "[1 2]", new_gene_vec(1, 2)

test_interpreter "{}", OrderedTable[string, Value]()
test_interpreter "{^a 1}", {"a": new_gene_int(1)}.toOrderedTable

# test_interpreter "(:test 1 2)", proc(r: Value) =
#   check r.gene_type == new_gene_symbol("test")
#   check r.gene_data[0] == 1
#   check r.gene_data[1] == 2

test_interpreter "(range 0 100)", proc(r: Value) =
  check r.range.start == 0
  check r.range.end == 100

test_interpreter "(0 .. 100)", proc(r: Value) =
  check r.range.start == 0
  check r.range.end == 100

test_interpreter "(1 + 2)", 3
test_interpreter "(1 - 2)", -1

test_interpreter """
  (var i 1)
  (i += 2)
  i
""", 3

test_interpreter """
  (var i 3)
  (i -= 2)
  i
""", 1

test_interpreter """
  (var i 1)
""", 1

# test_interpreter """
#   (var i 1 nil)
# """, nil

# test_interpreter """
#   (var i 1 2)
# """, 2

test_interpreter "(1 == 1)", true
test_interpreter "(1 == 2)", false
test_interpreter "(1 < 0)", false
test_interpreter "(1 < 1)", false
test_interpreter "(1 < 2)", true
test_interpreter "(1 <= 0)", false
test_interpreter "(1 <= 1)", true
test_interpreter "(1 <= 2)", true

test_interpreter "(true && true)", true
test_interpreter "(true && false)", false
test_interpreter "(false && false)", false
test_interpreter "(true || true)", true
test_interpreter "(true || false)", true
test_interpreter "(false || false)", false

test_interpreter "(var a 1) a", 1
test_interpreter "(var a 1) (a = 2) a", 2
test_interpreter "(var a) (a = 2) a", 2

test_interpreter """
  (var a 1)
  (var b 2)
  [a b]
""", proc(r: Value) =
  check r.vec[0] == 1
  check r.vec[1] == 2

test_interpreter """
  (var a 1)
  (var b 2)
  {^a a ^b b}
""", proc(r: Value) =
  check r.map["a"] == 1
  check r.map["b"] == 2

test_interpreter """
  (var a 1)
  (var b 2)
  (:test ^a a b)
""", proc(r: Value) =
  check r.gene_props["a"] == 1
  check r.gene_data[0] == 2

test_interpreter "(if true 1)", 1
test_interpreter "(if true then 1)", 1
test_interpreter "(if not false 1)", 1
test_interpreter "(if false 1 else 2)", 2
test_interpreter """
  (if false
    1
  elif true
    2
  else
    3
  )
""", 2

test_interpreter "(if* true 1)", 1
test_interpreter """
  (var a if*)
  (a true 1)
""", 1

test_interpreter "(do 1 2)", 2

test_interpreter """
  (void 1 2)
""", proc(r: Value) =
  check r == nil

test_interpreter """
  ($with 1
    self
  )
""", 1

test_interpreter """
  ($tap 1
    (assert (self == 1))
    2
  )
""", 1

test_interpreter """
  ($tap 1 :i
    (assert (i == 1))
    2
  )
""", 1

test_interpreter """
  (var a 1)
  ($tap a :i
    (assert (i == 1))
    2
  )
""", 1

test_interpreter """
  (var i 0)
  (loop
    (i = (i + 1))
    (break)
  )
  i
""", 1

test_interpreter """
  (var i 0)
  (loop
    (i += 1)
    (if (i < 5)
      (continue)
    else
      (break)
    )
    (i = 10000)  # should not reach here
  )
  i
""", 5

test_interpreter """
  (var i 0)
  (while (i < 3)
    (i += 1)
  )
  i
""", 3

test_interpreter """
  (var i 0)
  (while true
    (i += 1)
    (if (i < 3)
      (continue)
    else
      (break)
    )
    (i = 10000)  # should not reach here
  )
  i
""", 3

test_interpreter "self", Nil

# # test_interpreter """
# #   (call_native "str_size" "test")
# # """, 4

test_interpreter """
  (var a 1)
  (eval :a)
""", 1

test_interpreter """
  (var a 1)
  (var b 2)
  (eval :a :b)
""", 2

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

test_interpreter """
  (var a [2 3])
  [1 a... 4]
""", @[1, 2, 3, 4]

# test_interpreter """
#   [1 (... [2 3]) 4]
# """, @[1, 2, 3, 4]

# test "Interpreter / eval: native function (test)":
#   init_all()
#   VM.app.ns["test"] = proc(props: OrderedTable[MapKey, Value], data: seq[Value]): Value =
#     1
#   var code = cleanup """
#     (test)
#   """
#   check VM.eval(code) == 1

# test "Interpreter / eval: native function (test 1 2)":
#   init_all()
#   VM.app.ns["test"] = proc(props: OrderedTable[MapKey, Value], data: seq[Value]): Value =
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

test_interpreter """
  ($parse "true")
""", true

test_interpreter """
  (eval ($parse "(1 + 2)"))
""", 3

# test_interpreter """
#   ($include "tests/fixtures/include_example.gene")
#   a
# """, 100

# test_interpreter """
#   [
#     ($include "tests/fixtures/include_example.gene")
#   ]
# """, @[1, 2, 3]

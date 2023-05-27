import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

test_interpreter """
  ((nil .class).name)
""", "Nil"

test_interpreter """
  (nil .to_s)
""", ""

test_interpreter """
  (:a .to_s)
""", "a"

test_interpreter """
  ("a" .to_s)
""", "a"

test_interpreter """
  ([1 "a"] .to_s)
""", "[1 \"a\"]"

test_interpreter """
  ({^a "a"} .to_s)
""", "{^a \"a\"}"

test_interpreter """
  ((:x ^a "a" "b") .to_s)
""", "(x ^a \"a\" \"b\")"

test_interpreter """
  (class A
    (.fn call [x y]
      (x + y)
    )
  )
  (var a (new A))
  (a 1 2)   # is equivalent to (a .call 1 2)
""", 3

# test "GeneAny":
#   var s = "abc"
#   var g = Value(
#     kind: VkAny,
#     any: cast[pointer](s.addr),
#   )
#   check cast[ptr string](g.any)[] == s

# test_interpreter "gene", proc(r: Value) =
#   check r.ns.name == "gene"

# test_interpreter "genex", proc(r: Value) =
#   check r.ns.name == "genex"

# test_interpreter "(assert true)"

# test_interpreter "(AssertionError .name)","AssertionError"

# test_interpreter """
#   $runtime
# """, proc(r: Value) =
#   check r.runtime.pkg.home == "/Users/gcao/proj/gene.nim"
#   check r.runtime.pkg.version == "0.1.0"

# test_interpreter """
#   (var sum 0)
#   (4 .times (i -> (sum += i)))
#   sum
# """, 6 # 0 + 1 + 2 + 3

# # CSV separated by \t
# # first\tsecond
# # 1\t2
# # 10\t20
# test_interpreter """
#   (gene/csv/parse_string
# "first\tsecond
# 1\t2
# 10\t20")
# """, @[
#   new_gene_vec(@["1", "2"]),
#   new_gene_vec(@["10", "20"]),
# ]

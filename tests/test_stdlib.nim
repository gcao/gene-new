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
  ((1 ^a "a" "b") .to_s)
""", "(1 ^a \"a\" \"b\")"

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

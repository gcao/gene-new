import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

test_interpreter """
  ([1 2] .size)
""", 2

test_interpreter """
  ([1 2] .@ 0)
""", 1

test_interpreter """
  (var v [1 2])
  ($set v 0 3)
  v
""", @[3, 2]

test_interpreter """
  ([1 2] .add 3)
""", @[1, 2, 3]

test_interpreter """
  ([1 2] .del 0)
""", 1

test_interpreter """
  (var sum 0)
  ([1 2 3] .each (i -> (sum += i)))
  sum
""", 6

test_interpreter """
  ([1 2] .map (i -> (i + 1)))
""", @[2, 3]

test_interpreter """
  (fn inc i (i + 1))
  ([1 2] .map inc)
""", @[2, 3]

# test_interpreter """
#   ([1 2 3] .filter (i -> (i >= 2)))
# """, @[2, 3]

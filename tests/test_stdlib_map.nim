import unittest

import gene/types

import ./helpers

test_interpreter """
  ({^a 1 ^b 2} .size)
""", 2

# test_interpreter """
#   ({^a 1 ^b 2} .keys)
# """, @[new_gene_string("a"), new_gene_string("b")]

# test_interpreter """
#   ({^a 1 ^b 2} .values)
# """, @[1, 2]

# test_interpreter """
#   (var sum 0)
#   ({^a 1 ^b 2} .each
#     ([_ v] -> (sum += v))
#   )
#   sum
# """, 3

test_interpreter """
  ({} .map
    ([_ v] -> v)
  )
""", @[]

test_interpreter """
  ({^a 1 ^b 2} .map
    ([k v] -> k)
  )
""", proc(r: Value) =
  check r.vec.len == 2
  check r.vec.contains("a")
  check r.vec.contains("b")

test_interpreter """
  ({^a 1 ^b 2} .map
    ([_ v] -> v)
  )
""", proc(r: Value) =
  check r.vec.len == 2
  check r.vec.contains(1)
  check r.vec.contains(2)

import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

test_interpreter """
  ([1 2] .size)
""", 2

# test_interpreter """
#   ([1 2] .get 0)
# """, 1

# test_interpreter """
#   (var v [1 2])
#   (v .set 0 3)
#   v
# """, @[new_gene_int(3), new_gene_int(2)]

test_interpreter """
  ([1 2] .add 3)
""", @[new_gene_int(1), new_gene_int(2), new_gene_int(3)]

test_interpreter """
  ([1 2] .del 0)
""", 1

# test_interpreter """
#   (var sum 0)
#   ([1 2 3] .each (i -> (sum += i)))
#   sum
# """, 6

# test_interpreter """
#   ([1 2] .map (i -> (i + 1)))
# """, @[new_gene_int(2), new_gene_int(3)]

# test_interpreter """
#   ([1 2 3] .filter (i -> (i >= 2)))
# """, @[new_gene_int(2), new_gene_int(3)]

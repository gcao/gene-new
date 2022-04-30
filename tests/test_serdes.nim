import tables
import unittest

import gene/types

import ./helpers

test_serdes """
  1
""", 1

test_serdes """
  "abc"
""", "abc"

test_serdes """
  [1 2]
""", @[1, 2]

test_serdes """
  {^a 1}
""", {"a": new_gene_int(1)}.toTable

test_serdes """
  (1 ^a 2 3 4)
""", proc(r: Value) =
  check r.gene_type == 1
  check r.gene_props == {"a": new_gene_int(2)}.toTable
  check r.gene_children == @[3, 4]

# test_serdes """
#   (class A)
#   (new A)
# """, proc(r: Value) =
#   check r.class.name == "A"

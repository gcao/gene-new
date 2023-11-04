import unittest, tables

import gene/types

import ./helpers

test_vm """
  (macro m [])
""", proc(r: Value) =
  check r.macro.name == "m"

test_vm """
  (macro m a
    a
  )
  (m b)
""", new_gene_symbol("b")

test_vm """
  (macro m [a b]
    (a + b)
  )
  (m 1 2)
""", 3
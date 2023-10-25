import unittest, tables

import gene/types

import ./helpers

test_vm """
  (fn f []
  )
""", proc(r: Value) =
  check r.fn.name == "f"

test_vm """
  (fn f []
    1
  )
  (f)
""", 1

test_vm """
  (fn f [a]
    (a + 1)
  )
  (f 1)
""", 2

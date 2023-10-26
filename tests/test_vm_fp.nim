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

test_vm """
  (fn f [a b]
    (a + b)
  )
  (f 1 2)
""", 3

test_vm """
  (fn f []
    (return 1)
    2
  )
  (f)
""", 1

import unittest, tables

import gene/types

import ./helpers

test_vm """
  (fn f []
  )
""", proc(r: Value) =
  check r.fn.name == "f"

test_vm """
  ($_print_instructions)
  (fn f []
    ($_print_instructions)
    1
  )
  (f)
""", 1

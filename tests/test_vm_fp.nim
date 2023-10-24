import unittest, tables

import gene/types

import ./helpers

test_vm """
  (fn f _
  )
""", proc(r: Value) =
  check r.fn.name == "f"

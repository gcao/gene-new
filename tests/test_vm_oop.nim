import unittest, tables

import gene/types

import ./helpers

test_vm """
  (class A)
""", proc(r: Value) =
  check r.class.name == "A"

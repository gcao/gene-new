import unittest, tables

import gene/types

import ./helpers

test_vm """
  (ns n)
""", proc(r: Value) =
  check r.ns.name == "n"

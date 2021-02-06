import unittest, tables

import gene/types

import ./helpers

test_extension "tests/libextension", "test", proc(r: NativeFn) =
  var props = OrderedTable[string, GeneValue]()
  var data = @[new_gene_int(1), new_gene_int(2)]
  check r(props, data) == 3

test_interpreter """
  (import_native test from "tests/libextension")
  (test 1 2)
""", 3

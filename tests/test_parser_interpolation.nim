import unittest, tables

import gene/types

import ./helpers

test_parser """
  #"abc"
""", "abc"

test_parser """
  #"a#{b}c"
""", proc(r: Value) =
  check r.gene_type == new_gene_symbol("#Str")
  check r.gene_children[0] == "a"
  check r.gene_children[1] == new_gene_symbol("b")
  check r.gene_children[2] == "c"

test_parser """
  #"a#[]c"
""", proc(r: Value) =
  check r.gene_type == new_gene_symbol("#Str")
  check r.gene_children[0] == "a"
  check r.gene_children[1] == new_gene_vec()
  check r.gene_children[2] == "c"

test_parser """
  #"a#(b)c"
""", proc(r: Value) =
  check r.gene_type == new_gene_symbol("#Str")
  check r.gene_children[0] == "a"
  check r.gene_children[1] == new_gene_gene(new_gene_symbol("b"))
  check r.gene_children[2] == "c"

test_parser """
  #"a#{^^b}c"
""", proc(r: Value) =
  check r.gene_type == new_gene_symbol("#Str")
  check r.gene_children[0] == "a"
  check r.gene_children[1] == {"b": new_gene_bool(true)}.toTable
  check r.gene_children[2] == "c"

test_parser """
  #"a#{{^^b}}c"
""", proc(r: Value) =
  check r.gene_type == new_gene_symbol("#Str")
  check r.gene_children[0] == "a"
  check r.gene_children[1] == {"b": new_gene_bool(true)}.toTable
  check r.gene_children[2] == "c"

test_parser """
  #"a#<b>#c"
""", "ac"

test_parser "#\"\"\"abc\"\"\"", "abc"

test_parser "#\"\"\"a#{b}c\"\"\"", proc(r: Value) =
  check r.gene_type == new_gene_symbol("#Str")
  check r.gene_children[0] == "a"
  check r.gene_children[1] == new_gene_symbol("b")
  check r.gene_children[2] == "c"

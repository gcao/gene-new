import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

test_core "((\"\" .class) .name)", "String"

test_core "(\"abc\" .size)", 3

test_core "(\"abc\" .substr 1)", "bc"
test_core "(\"abc\" .substr -1)", "c"
test_core "(\"abc\" .substr -2 -1)", "bc"

test_core "(\"a:b:c\" .split \":\")", @[new_gene_string("a"), new_gene_string("b"), new_gene_string("c")]
test_core "(\"a:b:c\" .split \":\", 2)", @[new_gene_string("a"), new_gene_string("b:c")]

test_core "(\"abc\" .index \"b\")", 1
test_core "(\"abc\" .index \"x\")", -1

test_core "(\"aba\" .rindex \"a\")", 2
test_core "(\"abc\" .rindex \"x\")", -1

test_core "(\"  abc  \" .trim)", "abc"

test_core "(\"abc\" .starts_with \"ab\")", true
test_core "(\"abc\" .starts_with \"bc\")", false

test_core "(\"abc\" .ends_with \"ab\")", false
test_core "(\"abc\" .ends_with \"bc\")", true

test_core "(\"abc\" .to_upper_case)", "ABC"
test_core "(\"ABC\" .to_upper_case)", "ABC"

test_core "(\"abc\" .to_lower_case)", "abc"
test_core "(\"ABC\" .to_lower_case)", "abc"

test_core "(\"abc\" .char_at 1)", 'b'

test_core "(\"a\" nil true 1 :symbol)", "atrue1symbol"

test_core """
  (var s "a")
  (s .append "b")
  (s .append "c")
  s
""", "abc"

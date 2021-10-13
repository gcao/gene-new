import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

test_interpreter "((\"\" .class) .name)", "String"

test_interpreter "(\"abc\" .size)", 3

test_interpreter "(\"abc\" .substr 1)", "bc"
test_interpreter "(\"abc\" .substr -1)", "c"
test_interpreter "(\"abc\" .substr -2 -1)", "bc"

test_interpreter "(\"a:b:c\" .split \":\")", @[new_gene_string("a"), new_gene_string("b"), new_gene_string("c")]
test_interpreter "(\"a:b:c\" .split \":\", 2)", @[new_gene_string("a"), new_gene_string("b:c")]

test_interpreter "(\"abc\" .index \"b\")", 1
test_interpreter "(\"abc\" .index \"x\")", -1

test_interpreter "(\"aba\" .rindex \"a\")", 2
test_interpreter "(\"abc\" .rindex \"x\")", -1

test_interpreter "(\"  abc  \" .trim)", "abc"

test_interpreter "(\"abc\" .starts_with \"ab\")", true
test_interpreter "(\"abc\" .starts_with \"bc\")", false

test_interpreter "(\"abc\" .ends_with \"ab\")", false
test_interpreter "(\"abc\" .ends_with \"bc\")", true

test_interpreter "(\"abc\" .to_uppercase)", "ABC"
test_interpreter "(\"ABC\" .to_uppercase)", "ABC"

test_interpreter "(\"abc\" .to_lowercase)", "abc"
test_interpreter "(\"ABC\" .to_lowercase)", "abc"

test_interpreter "(\"abc\" .char_at 1)", 'b'

# test_interpreter "(\"a\" nil true 1 :symbol)", "(\"a\" nil true 1 :symbol)"

test_interpreter """
  (var s "a")
  (s .append "b")
  (s .append "c")
  s
""", "abc"

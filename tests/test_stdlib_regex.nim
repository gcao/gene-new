import unittest, tables

import gene/types

import ./helpers

# test_interpreter """
#   ((#/a/ .class).name)
# """, "Pattern"

test_interpreter """
  (("a" =~ #/a/).to_bool)
""", true

test_interpreter """
  ("a" !~ #/a/)
""", Nil

import unittest

import gene/types

import ./helpers

test_serdes """
  1
""", proc(r: Value) =
  check r == 1

# test_serdes """
#   (class A)
#   (new A)
# """, proc(r: Value) =
#   check r.class.name == "A"

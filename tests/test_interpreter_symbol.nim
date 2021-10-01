import unittest

import gene/types

import ./helpers

test_interpreter """
  (ns n
    (ns m
      (class C)
    )
  )
  n/m/C
""", proc(r: Value) =
  check r.class.name == "C"

# test_interpreter """
#   (class C
#     (mixin M
#       (fn f _ 1)
#     )
#   )
#   (C/M/f)
# """, 1

# test_interpreter """
#   (enum A first second)
#   A/second
# """, proc(r: Value) =
#   var m = r.enum_member
#   check m.parent.name == "A"
#   check m.name == "second"
#   check m.value == 1

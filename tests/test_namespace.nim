import unittest

import gene/types
import gene/interpreter

import ./helpers

test_interpreter "(ns test)", proc(r: Value) =
  check r.ns.name == "test"

test_interpreter """
  (ns n
    (class A)
  )
  n/A
""", proc(r: Value) =
  check r.class.name == "A"

test_interpreter """
  (ns n)
  (ns n/m)
  n/m
""", proc(r: Value) =
  check r.ns.name == "m"

# test_interpreter """
#   (ns n)
#   (ns n/m
#     (class A)
#   )
#   n/m/A
# """, proc(r: Value) =
#   check r.internal.class.name == "A"

test_interpreter """
  (ns n)
  n
""", proc(r: Value) =
  check r.ns.name == "n"

# test_core "(global .name)", "global"

# test_interpreter """
#   (class global/A)
#   global/A
# """, proc(r: Value) =
#   check r.internal.class.name == "A"

# test_interpreter """
#   (var global/a 1)
#   a
# """, 1

# test_interpreter """
#   (class A
#     (fn f a a)
#   )
#   (A/f 1)
# """, 1

# # test_interpreter """
# #   (ns n
# #     (member_missing
# #       (fnx [self name]
# #         "not found"
# #       )
# #     )
# #   )
# #   n/A  # only when a name is accessed using a/X or a/b/X, member_missing is triggered
# # """, "not found"

# test_interpreter """
#   (ns n
#     (class A)
#     (ns m
#       (class B < A)
#     )
#   )
#   n/m/B
# """, proc(r: Value) =
#   check r.internal.class.name == "B"

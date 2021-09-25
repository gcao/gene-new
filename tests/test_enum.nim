import unittest, tables

import gene/types

import ./helpers

# test_interpreter """
#   (enum A first second)
#   A
# """, proc(r: Value) =
#   var e = r.internal.enum
#   check e.name == "A"
#   check e.members.len == 2
#   check e.members["first"].name == "first"
#   check e.members["first"].value == 0
#   check e.members["second"].name == "second"
#   check e.members["second"].value == 1

# test_interpreter """
#   (enum A
#     first = 1
#     second      # value will be 2
#   )
#   A/second
# """, proc(r: Value) =
#   var m = r.internal.enum_member
#   check m.parent.name == "A"
#   check m.name == "second"
#   check m.value == 2

# test_interpreter """
#   (enum A first second)
#   A/second/name
# """, "second"

# test_interpreter """
#   (enum A first second)
#   A/second/value
# """, 1

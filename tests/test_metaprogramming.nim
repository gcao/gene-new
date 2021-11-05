import unittest

import gene/types

import ./helpers

# Ideas:
# * Namespace.member_defined (called when a member is defined or re-defined)
# * Namespace.member_removed
# * Namespace.member_missing (invoked only if <some_ns>/something is invoked and something is not defined)

# * object created
# * object destroyed - how do we know an object is destroyed?

# * method_defined (called when a method is defined or re-defined)
# * method_removed
# * method_missing

# * class extended - can not be unextended
# * mixin included - can not be removed

# * module imported

# * aspect applied
# * aspect disabled
# * aspect enabled
# * ...

test_interpreter """
  (ns n
    (member_missing _
      (if ($member_name == "test")
        1
      else
        (throw ("Member missing: " $member_name))
      )
    )
  )
  n/test
""", 1

test_interpreter """
  (ns n
    (member_missing _
      ("" self/.name "/" $member_name)
    )
  )
  n/test
""", "n/test"

test_interpreter """
  (class C
    (member_missing _
      ("" self/.name "/" $member_name)
    )
  )
  C/test
""", "C/test"

# test_interpreter """
#   (class C
#     (method_missing _
#       ("" self/.class/.name "." $method_name)
#     )
#   )
#   ((new C).test)
# """, "C.test"

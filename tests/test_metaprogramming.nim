import unittest

import gene/types

import ./helpers

# Ideas:
# * Namespace.member_defined (called when a member is defined or re-defined)
# * Namespace.member_removed
# * Namespace.member_missing (invoked only if <some_ns>/something is invoked and something is not defined)
# * Namespace.has_member - it should be consistent with member_missing

# * object created
# * object destroyed - how do we know an object is destroyed?

# * method_defined (called when a method is defined or re-defined)
# * method_removed
# * method_missing
# * respond_to - whether it'll respond to a method name, it should be consistent with method_missing

# * class extended - can not be unextended
# * mixin included - can not be removed

# * module imported

# * aspect applied
# * aspect disabled
# * aspect enabled
# * ...

test_interpreter """
  (ns n
    (member_missing name
      (if (name == "test")
        1
      else
        # What should we do here, in order to pass to the next namespace to search for the name?
        # Option 1: ($get_member self/.parent)
        # Option 3: ($member_missing name)
        # Option 2: (throw (new MemberNotFound name))
      )
    )
  )
  n/test
""", 1

test_interpreter """
  (ns n
    (member_missing name
      ("" self/.name "/" name)
    )
  )
  n/test
""", "n/test"

test_interpreter """
  (class C
    (member_missing name
      ("" self/.name "/" name)
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

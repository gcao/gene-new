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

# test_interpreter """
#   (class C
#     (method_missing _
#       ("" self/.class/.name "." $method_name)
#     )
#   )
#   ((new C).test)
# """, "C.test"

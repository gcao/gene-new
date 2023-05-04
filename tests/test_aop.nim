import gene/types

import ./helpers

# The goal should be to provide a building block that can work well with other
# functionalities and can be used to implement more complex behaviors.
# The goal should NOT be to provide functionalities that are covered by other features
# in the language (e.g. OOP, FP, inheritance, mixins, etc.)

# Concepts

# AOP for classes
# * Aspect (group of advices)
# * Advice (before instantiation, after instantiation, before method call, after method call, around method call)
# * Target (class)
# * Interception (instance of an aspect applied to a target)

# AOP for functions/macros
# * SimpleAdvice (before call, after call, around call)
# * Target (function/macro)
# * SimpleInterception (instance of an advice applied to a target)

# Targets after interception should work similar to the original target
# For example:
# * A function should be callable and should still be a function instead of a macro
# * A class should still be a class

# For simplicity's sake, we don't need Aspect for functions/macros.
# We can just apply the advices directly to the function/macro.

# AOP(Aspect Oriented Programming):
#
# * before
# * after
# * around
#
# * Can alter arguments (The same args object must be passed to the advices)
# * Can alter result
# * Can add functionality
# * Can skip run
# * Can trigger retry
# * ...
#
# Aspects should be grouped, but how?
# * OOP:
#   on class level
#
# * Functions:
#   on scope/ns level, a new object with same name is created in
#   the ns/scope which stores a reference of the old function object
#
# Design by Contract - can be implemented with AOP
# * precondition
# * postcondition
# * invariant
#

# test_interpreter """
#   # aspect: define aspects that are applicable to classes
#   (aspect A [target m] # target is required, m is the matcher for arguments passed in when applied
#     (.before_call m (fnx a
#       ($args/0 = (a + 1)) # have to update the args object
#     ))
#   )
#   (class C
#     (.fn test a
#       a
#     )
#   )
#   (var applied (A C "test")) # save the reference to disable later if needed
#   ((new C) .test 1)
# """, 2

test_interpreter """
  (fn f a
    a
  )
  # (before f ...) will return a new object not associated with "f"
  # (var f ...)    will associate the new object with "f"
  (f = (before f
    (fnx a
      ($args/0 = (a + 2)) # have to update the $args object, changing a will not affect the original $args object.
    )
  ))
  (f 1)
  # (f = f/.wrapped) # replace f with the original function that was wrapped
""", 3

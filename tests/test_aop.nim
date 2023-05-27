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
# * before_filter: conditional logic that runs before the target, if false, the target is not run
# * before_and_after: logic that runs before and after the target
# * after
# * after_error
# * around
#
# * Can alter arguments (The same *$args* object must be passed to the advices)
# * Can alter result (The $result object is shared between the target and the *after* advices)
# * Can add functionality
# * Can skip run (supported by *before_filter* and *around*)
# * Can trigger retry (supported by *around*)
# * Can catch errors (supported by *after_error* and *around*)
# * ...
#
# Aspects should be grouped, but how?
# * OOP:
#   on class level
#
# * Functions:
#   on scope/ns level, a new object with the same name is created in
#   the ns/scope which stores a reference of the old function object
#
# Design by Contract - can be implemented with AOP
# * precondition
# * postcondition
# * invariant
#

# test_interpreter """
#   # aspect: define aspects that are applicable to classes
#   (aspect A [m] # m is the matcher for arguments passed in when applied
#     # self/.target is the class object
#     (.before_method m (fnx a
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

test_interpreter """
  (fn f a
    a
  )
  (f = (after f
    (fnx a
      ($result += 2)
    )
  ))
  (f 1)
""", 3

# test_interpreter """
#   (fn f a
#     a
#   )
#   (f = (around f
#     (fnx a
#       (($call_target) + 2) # $call_target triggers the wrapped function with the same args
#     )
#   ))
#   (f 1)
# """, 3

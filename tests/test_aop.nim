import gene/types

import ./helpers

# AOP(Aspect Oriented Programming):
#
# * before
# * after
# * around
#
# * Can alter arguments
# * Can alter result
# * Can skip run
# * Can trigger retry
# * ...
#
# * AOP for OOP
#   Can be applied to classes and methods
#
# * AOP for functions
#   Can be applied to existing functions (not macros and blocks)
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
#   # claspect: define aspects that are applicable to classes
#   (claspect A [target m] # target is required, m is the matcher for arguments passed in when applied
#     (before m (fnx a
#       ($set $args 0 (a + 1)) # have to update the args object
#     ))
#   )
#   (class C
#     (.fn test a
#       a
#     )
#   )
#   (var applied (A C "test")) # save the reference to disable later
#   ((new C) .test 1)
# """, 2

test_interpreter """
  # aspect: define aspects that are applicable to functions
  (aspect A [target arg]
    (before target (fnx a
      ($set $args 0 (a + arg)) # have to update the args object
    ))
  )
  (fn f a
    a
  )
  (var f (A f 2)) # re-define f in current scope
  (f 1)
  # (f .unwrap) # return the function that was wrapped
""", 3

test_interpreter """
  # aspect: define aspects that are applicable to functions
  (aspect A [target arg]
    (before target (fnx a
      ($set $args 0 (a + arg)) # have to update the args object
    ))
  )
  (fn f a
    a
  )
  (var f (A f 2)) # re-define f in current scope
  (var f (A f 3)) # re-define f in current scope
  (f 1)
""", 6

# test_interpreter """
#   # aspect: define aspects that are applicable to functions
#   (aspect A [target arg]
#     (after target (fnx a
#       # TODO
#     ))
#   )
#   (fn f a
#     a
#   )
#   (var f (A f 2)) # re-define f in current scope
#   (f 1)
# """, 3

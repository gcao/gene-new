import unittest

import gene/types

import ./helpers

# Functional programming:
#
# * Return function as result
# * Pass function around
# * Closure
# * Iterators
# * Pure function (mark function as pure, all standard lib should be marked pure if true)
# * Continuation - is it possible?
#
# * Native function
#   proc(props: OrderedTable[string, Value], data: openarray[Value]): Value
# * Native method
#   Simple: proc(
#     self: Value,
#     props: OrderedTable[string, Value],
#     data: openarray[Value],
#   ): Value
#   Complex: proc(
#     caller: Frame,
#     options: Table[FnOption, Value],
#     self: Value,
#     props: OrderedTable[string, Value],
#     data: openarray[Value],
#   ): Value
#
# How do we support "self" inside function?
# self = true to allow self to be used inside function
# inherit_self = true to automatically inherit self in the caller's context
# (fn ^^self f [^a b]
#   (.size)
# )
# (call f ^self "" (_ ^a 2 3))
# ("" >> f ^a 1 2)    # A shortcut to call f with self, (call ...) is the generic form
# (>> f ^a 1 2)       # A shortcut to call f with self from current scope

test_interpreter "(fn f a a)", proc(r: Value) =
  check r.fn.name == "f"

# test_interpreter "(fn f _)", proc(r: Value) =
#   check r.fn.matcher.children.len == 0

test_interpreter """
  (fn f [] 1)
  (f)
""", 1

test_interpreter """
  (fn f a (a + 1))
  (f 1)
""", 2

test_interpreter """
  (fn f _ self)
  (1 . f)
""", 1

# test_interpreter """
#   (fn f [a = 1] a)
#   (f)
# """, 1

# test_interpreter """
#   (fn f [a = 1] a)
#   (f 2)
# """, 2

# test_interpreter """
#   (fn f [a b = a] b)
#   (f 1)
# """, 1

# test_interpreter """
#   (fn f [a b = (a + 1)] b)
#   (f 1)
# """, 2

# test_interpreter """
#   (fn f _
#     (return 1)
#     2
#   )
#   (f)
# """, 1

test_interpreter """
  (fn fib n
    (if (n < 2)
      n
    else
      ((fib (n - 1)) + (fib (n - 2)))
    )
  )
  (fib 6)
""", 8

# test_interpreter """
#   (fn f _
#     (fn g a a)
#   )
#   ((f) 1)
# """, 1

# test_interpreter """
#   (fn f a
#     (fn g _ a)
#   )
#   ((f 1))
# """, 1

# test_interpreter """
#   (fn f _
#     (var r return)
#     (r 1)
#     2
#   )
#   (f)
# """, 1

# # return can be assigned and will remember which function
# # to return from
# # Caution: "r" should only be used in nested functions/blocks inside "f"
# test_interpreter """
#   (fn g ret
#     (ret 1)
#   )
#   (fn f _
#     (var r return)
#     (loop
#       (g r)
#     )
#   )
#   (f)
# """, 1

# # return can be assigned and will remember which function
# # to return from
# test_interpreter """
#   (fn f _
#     (var r return)
#     (fn g _
#       (r 1)
#     )
#     (loop
#       (g)
#     )
#   )
#   (f)
# """, 1

# test_interpreter """
#   (fn f _ $args)
#   (f 1)
# """, proc(r: Value) =
#   check r.gene.data[0] == 1

# test_interpreter """
#   (fn f [a b] (a + b))
#   (fn g _
#     (f ...)
#   )
#   (g 1 2)
# """, 3

# test_interpreter """
#   (var f
#     (fnx a a)
#   )
#   (f 1)
# """, 1

# test_interpreter """
#   (var f
#     (fnxx 1)
#   )
#   (f)
# """, 1

# test_interpreter """
#   (fn f _ 1)    # first f in namespace
#   (var f        # second f in scope
#     (fnx _
#       ((f) + 1) # reference to first f because second f is defined after the anonymous function
#     )
#   )
#   (f)           # second f
# """, 2

# test_interpreter """
#   (fn f [^a] a)
#   (f ^a 1)
# """, 1

# test_interpreter """
#   (fn f _ 1)
#   (call f)
# """, 1

# test_interpreter """
#   (fn f [a b] (a + b))
#   (call f [1 2])
# """, 3

# # # Should throw error because we expect call takes a single argument
# # # which must be an array, a map or a gene that will be exploded
# # test_interpreter """
# #   (fn f [a b] (a + b))
# #   (call f 1 2)
# # """, 1

# test_interpreter """
#   (fn f [^a b] (a + b))
#   (call f (_ ^a 1 2))
# """, 3

# # test_interpreter """
# #   (fn f [^a b] (self + a + b))
# #   (call f ^self 1 (_ ^a 2 3))
# # """, 6

# # test_interpreter """
# #   (fn f a
# #     (self + a)
# #   )
# #   (1 >> f 2)
# # """, 3

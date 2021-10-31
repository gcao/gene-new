import unittest

import gene/types

import ./helpers

#
# Support blocks like Ruby block
#
# * Good for iterators etc
# * yield:
# * return: return from the calling function, not from the iterator function
# * next:
# * break
#
# Block syntax
# (-> ...)
# (a -> ...)
# ([a b] -> ...)
#
# If last argument is a block, a special block argument is accessible
#
# (yield 1 2) will call the block with arguments and return value
# from the block
#
# Maybe there is not need for special syntax like Ruby, we can invoke
# it like regular function
#

test_interpreter """
  (->)
""", proc(r: Value) =
  check r.kind == VkBlock

test_interpreter """
  (a -> a)
""", proc(r: Value) =
  check r.kind == VkBlock

test_interpreter """
  (var b (-> 1))
  (b)
""", 1

test_interpreter """
  (var b (a -> a))
  (b 1)
""", 1

test_interpreter """
  (var a 1)
  (var b (-> a))
  (b)
""", 1

test_interpreter """
  (fn f block
    (var a 1)
    (block a)
  )
  (f (a -> a))
""", 1

# test_interpreter """
#   (fn f b
#     (b 1)
#     0
#   )
#   (fn g _
#     (f (a -> (return a)))
#   )
#   (g)
# """, 1

# test_interpreter """
#   (fn f b
#     (b 1)
#     0
#   )
#   (fn g _
#     (f (a -> (return $args)))  # $args is what is passed to the containing function ?
#   )
#   (g 2)
# """, proc(r: Value) =
#   check r.gene.data == @[2]

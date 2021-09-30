import unittest

import gene/types
import gene/interpreter

import ./helpers

# How built-in templates work:
# Any quoted value is a template: e.g. :(%a b)
# Interpret: (%a b)
# Render: ($render :(%a b)) => (<value of a> b)

# Is this the right behavior?
# test_interpreter """
#   (var tpl :(%f b))
#   (fn f a a)
#   (var x ($render tpl))
#   (eval x)
# """, new_gene_symbol("b")

test_interpreter """
  (var tpl :(%f %b))
  (fn f a (a + 1))
  (var b 2)
  (var x ($render tpl)) # => (<function f> 2)
  (eval x)
""", 3

# test_interpreter """
#   (var a 1)
#   :(test %a 2)
# """, proc(r: Value) =
#   check r.gene_type == new_gene_symbol("test")
#   check r.gene_data[0] == 1
#   check r.gene_data[1] == 2

# test_interpreter """
#   :(test
#     %%(var a 1)
#     %a
#     2
#   )
# """, proc(r: Value) =
#   check r.gene_type == new_gene_symbol("test")
#   check r.gene_data[0] == 1
#   check r.gene_data[1] == 2

# # test_interpreter """
# #   (var a [1 2])
# #   :(test
# #     %a...
# #     3
# #   )
# # """, proc(r: Value) =
# #   check r.gene_type == new_gene_symbol("test")
# #   check r.gene_data[0] == 1
# #   check r.gene_data[1] == 2
# #   check r.gene_data[2] == 3

# # TODO: nested quote/unquote, need more thoughts before implementing
# # test_interpreter """
# #   (var a 1)
# #   ::(test %a 2)
# # """, proc(r: Value) =
# #   check r == read(":(test %a 2)")

# # test_interpreter """
# #   (var a 1)
# #   ::(test %%a 2)
# # """, proc(r: Value) =
# #   check r == read(":(test 1 2)")

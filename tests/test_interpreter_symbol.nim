import unittest

import gene/types

import ./helpers

# Builtins:
# global
# gene
# genex
# self
# $ns
# $app
# $pkg
# $module
# $fn
# $class
# $method
# $args
# $ex

# a       # variable in current scope or namespace
# /a      # member of namespace
# @prop   # property of self object
# @1      # second entry of self.gene_data, or self.vec etc
# @-1     # last entry of self.gene_data, or self.vec etc

# TODO: Unify @prop, @1 and generic selector feature

# n/f     # member of namespace like objects (namespace, class, mixin)
# e/X     # member of enum
# x/@prop     # prop of x (instance or gene or map)
# x/.meth     # call meth on x  (shortcut for calling method without arguments)
# self/.meth  # call meth on self

# test_interpreter "(var /a 1) a", 1
# test_interpreter "(var /a 1) /a", 1

test_interpreter """
  $ns
""", proc(r: Value) =
  check r.ns.name == "<root>"

test_interpreter """
  (ns n
    (ns m
      (class C)
    )
  )
  n/m/C
""", proc(r: Value) =
  check r.class.name == "C"

test_interpreter """
  (class C
    (mixin M
      (fn f _ 1)
    )
  )
  (C/M/f)
""", 1

# test_interpreter """
#   (enum A first second)
#   A/second
# """, proc(r: Value) =
#   var m = r.enum_member
#   check m.parent.name == "A"
#   check m.name == "second"
#   check m.value == 1

import unittest

import gene/types

import ./helpers

# Builtins:
# global
# gene - standard library
# genex - additional or experimental standard library
# self
# $vm
# $app
# $pkg
# $module
# $ns
# $fn
# $class
# $method
# $args
# $ex

# a       # variable in current scope or namespace
# $ns/a   # member of namespace
# /prop   # property of self object
# /0      # first entry of self.gene_children, or self.vec etc
# /-1     # last entry of self.gene_children, or self.vec etc

# TODO: Unify access of properties, children and generic selector feature

# n/f     # member of namespace like objects (namespace, class, mixin)
# e/X     # member of enum
# x/prop     # prop of x (instance or gene or map)
# x/.meth     # call meth on x  (shortcut for calling method without arguments)
# self/.meth  # call meth on self

# test_interpreter "(var $ns/a 1) a", 1

test_interpreter """
  $app
""", proc(r: Value) =
  check r.app.ns.name == "global"

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

test_interpreter """
  (enum A first second)
  A/second
""", proc(r: Value) =
  var m = r.enum_member
  check m.parent.enum.name == "A"
  check m.name == "second"
  check m.value == 1

test_interpreter """
  (class C
    (.ctor _
      (/prop = 1)
    )
  )
  (var c (new C))
  c/prop
""", 1

test_interpreter """
  (class C
    (.ctor _
      (/prop = 1)
    )
  )
  (var c (new C))
  ($with c /prop)
""", 1

test_interpreter """
  (class C
    (.fn test _
      1
    )
  )
  (var c (new C))
  c/.test
""", 1

test_interpreter """
  (class C
    (.fn test _
      1
    )
  )
  (var c (new C))
  ($with c /.test)
""", 1

test_interpreter """
  (class C
    (.fn test _
      (/p = 1)
    )
  )
  ((new C).test)
""", 1

test_interpreter """
  (fn f _
    1
  )
  f/.call
""", 1

test_interpreter """
  (fn f _
    [1 2]
  )
  f/.call/0
""", 1

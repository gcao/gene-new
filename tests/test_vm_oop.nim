import unittest, tables

import gene/types

import ./helpers

test_vm """
  (class A)
""", proc(r: Value) =
  check r.class.name == "A"

test_vm """
  (class A)
  (class B < A)
""", proc(r: Value) =
  check r.class.name == "B"
  check r.class.parent.name == "A"

test_vm """
  (class A
    (class B)
  )
  A/B
""", proc(r: Value) =
  check r.class.name == "B"

test_vm """
  (class A)
  (new A)
""", proc(r: Value) =
  check r.instance_class.name == "A"

test_vm """
  (class A
    (.fn test _
      1
    )
  )
  ((new A).test)
""", 1

import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

test_interpreter """
  (ns n)
  n/.name
""", "n"

test_interpreter """
  (ns n
    (var /a 1)
  )
  n/.members
""", proc(r: Value) =
  check r.map.len == 1
  check r.map["a"] == 1

test_interpreter """
  (ns n
    (var /a 1)
  )
  n/.member_names
""", @["a"]

test_interpreter """
  (ns n)
  (n .has_member "a")
""", false

test_interpreter """
  (ns n
    (var /a 1)
  )
  (n .has_member "a")
""", true

test_interpreter """
  (class C)
  (C .has_member "a")
""", false

test_interpreter """
  (class C
    (var /a 1)
  )
  (C .has_member "a")
""", true

test_interpreter """
  (mixin M)
  (M .has_member "a")
""", false

test_interpreter """
  (mixin M
    (var /a 1)
  )
  (M .has_member "a")
""", true

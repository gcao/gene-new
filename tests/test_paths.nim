import unittest

import gene/types

import ./helpers

test_interpreter """
  $root/a/b
""", proc(r: Value) =
  check false

test_interpreter """
  ./a/b
""", proc(r: Value) =
  check false

test_interpreter """
  ../a/b
""", proc(r: Value) =
  check false

test_interpreter """
  */a/b
""", proc(r: Value) =
  check false

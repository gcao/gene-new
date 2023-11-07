import unittest
import bitops

import gene/value

test "Value kind":
  check NIL.kind == VkNil
  check VOID.kind == VkVoid
  check PLACEHOLDER.kind == VkPlaceholder

  check TRUE.kind == VkBool
  check FALSE.kind == VkBool

  check 0.Value.kind == VkInt

  var a = 1
  check a.addr.to_value().kind == VkPointer

  check 'a'.to_value().kind == VkChar

  check "abc".to_value().kind == VkString
  # check "abcdefghij".to_value().kind == VkString

test "Value conversion":
  check nil.to_value().is_nil() == true
  check nil.to_value() == NIL

  check true.to_value().to_bool() == true
  check false.to_value().to_bool() == false
  check NIL.to_bool() == false
  check 0.Value.to_bool() == true

  check 1.Value.to_int() == 1
  check 0x20.shl(56).Value.to_float() == 0.0
  check 1.1.to_value().to_float() == 1.1
  var a = 1
  check cast[ptr int64](a.addr.to_value().to_pointer())[] == 1

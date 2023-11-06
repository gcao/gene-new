import unittest
import bitops

import gene/value

test "Value kind":
  check 0.Value.kind == VkInt
  check NIL.kind == VkNil
  check VOID.kind == VkVoid
  check PLACEHOLDER.kind == VkPlaceholder
  check TRUE.kind == VkBool
  check FALSE.kind == VkBool
  var a = 1
  check a.addr.to_value().kind == VkPointer

test "Value conversion":
  check 0x20.shl(56).Value.to_float() == 0.0
  check 1.1.to_value().to_float() == 1.1
  check 0.Value.to_bool() == false
  var a = 1
  check cast[ptr int](a.addr.to_value().to_pointer())[] == 1

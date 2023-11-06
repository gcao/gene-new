import unittest

import gene/types

test "Value kind":
  check 0.kind == VkInt
  check NIL.kind == VKNil

test "Value conversion":
  check 0x20.shl(56).BasicValue.to_float() == 0.0

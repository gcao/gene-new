import tables, strutils

import ./map_key
import ./types
import ./normalizers

const SIMPLE_BINARY_OPS* = [
  "+", "-", "*", "/", "**",
  "==", "!=", "<", "<=", ">", ">=",
  "&&", "||", # TODO: xor
  "&",  "|",  # TODO: xor for bit operation
]

const COMPLEX_BINARY_OPS* = [
  "+=", "-=", "*=", "/=", "**=",
  "&&=", "||=", # TODO: xor
  "&=",  "|=",  # TODO: xor for bit operation
]

type
  Translator* = proc(node: Value): Value

proc translate*(node: Value): Value =
  case node.kind:
  of VkNil, VkBool, VkInt:
    return node
  of VkSymbol:
    todo()
  else:
    todo()

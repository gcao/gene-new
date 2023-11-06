import re, bitops, strformat

type
  ValueKind* = enum
    # void vs nil vs placeholder:
    #   void has special meaning in some places (e.g. templates)
    #   nil is the default/uninitialized value.
    #   placeholder can be interpreted any way we want
    VkVoid
    VkNil
    VkPlaceholder
    VkPointer
    VkBool
    VkInt
    VkFloat
    VkChar
    VkRune  # Unicode code point = u32

  Value* = distinct int64

const I64_MASK = 0xC000_0000_0000_0000u64
const F64_ZERO = 0x2000_0000_0000_0000u64

const NIL_PREFIX = 0x7FFA
const NIL* = cast[Value](0x7FFA_A000_0000_0000u64)

const BOOL_PREFIX = 0x7FFC
const TRUE*  = cast[Value](0x7FFC_A000_0000_0000u64)
const FALSE* = cast[Value](0x7FFC_0000_0000_0000u64)

const POINTER_PREFIX = 0x7FFB

const OTHER_PREFIX = 0x7FFE
const OTHER_MASK = 0x7FFE_FF00_0000_0000u64

const VOID* = cast[Value](0x7FFE_0000_0000_0000u64)
const PLACEHOLDER* = cast[Value](0x7FFE_0100_0000_0000u64)

const CHAR_PREFIX = 0xFFFE
const CHAR_MASK = 0xFFFE_0000_0000_0000u64

proc todo*() =
  raise new_exception(Exception, "TODO")

proc to_binstr*(v: int64): string =
  re.replacef(fmt"{v: 065b}", re.re"([01]{8})", "$1 ")

proc `==`*(a, b: Value): bool {.inline.} =
  cast[int64](a) == cast[int64](b)

proc kind*(v: Value): ValueKind {.inline.} =
  let v1 = cast[uint64](v)
  case cast[int](v1.shr(48)):
    of NIL_PREFIX:
      return VkNil
    of BOOL_PREFIX:
      return VkBool
    of POINTER_PREFIX:
      return VkPointer
    of CHAR_PREFIX:
      return VkChar
    of OTHER_PREFIX:
      let other_info = cast[Value](bitand(v1, OTHER_MASK))
      case other_info:
        of VOID:
          return VkVoid
        of PLACEHOLDER:
          return VkPlaceholder
        else:
          todo()
    else:
      if bitand(v1, I64_MASK) == 0:
        return VkInt
      else:
        return VkFloat

proc is_nil*(v: Value): bool {.inline.} =
  v == NIL

proc to_int*(v: Value): int64 {.inline.} =
  cast[int64](v)

proc to_float*(v: Value): float64 {.inline.} =
  if cast[uint64](v) == F64_ZERO:
    return 0.0
  else:
    return cast[float64](v)

proc to_value*(v: float64): Value {.inline.} =
  if v == 0.0:
    return cast[Value](F64_ZERO)
  else:
    return cast[Value](v)

proc to_bool*(v: Value): bool {.inline.} =
  not (v == FALSE or v == NIL)

proc to_value*(v: bool): Value {.inline.} =
  if v:
    return TRUE
  else:
    return FALSE

proc to_pointer*(v: Value): pointer {.inline.} =
  cast[pointer](bitand(cast[int64](v), 0x0000FFFFFFFFFFFF))

proc to_value*(v: pointer): Value {.inline.} =
  if v.is_nil:
    return NIL
  else:
    cast[Value](bitor(cast[int64](v), 0x7FFB000000000000))

proc to_char*(v: Value): char {.inline.} =
  todo()

proc to_value*(v: char): Value {.inline.} =
  cast[Value](bitor(CHAR_MASK, v.ord.uint64))

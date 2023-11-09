import tables, re, bitops, unicode, strformat

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
    VkString
    # VkRune  # Unicode code point = u32

    VkMap

  Value* = distinct int64

  Reference* = ref object
    case kind*: ValueKind
      of VkString:
        str*: string
      of VkMap:
        map*: Table[string, Value]
      else:
        discard

  # Design an efficient thread-local data structure to store all strings,
  # sequences, maps, references, and other objects that are not primitive

  # free(i) => available.push(i), data[i] = nil
  # get() => if available.empty() then data.push(nil) else available.pop()
  ManagedStrings = object
    data: seq[string]
    free: seq[int]

  # No symbols should be removed.
  ManagedSymbols = object
    data:  Table[string, int]
    data2: Table[int, string]

  ManagedReferences = object
    data: seq[Reference]
    free: seq[int]

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
# const RUNE_PREFIX = 0xFFFF
# const RUNE_MASK = 0xFFFF_0000_0000_0000u64

const EMPTY_STRING = 0x7FFA_0000_0000_0000u64
const STRING_PREFIX  = 0xFFFA
const STRING6_PREFIX = 0xFFFB
const STRING_MASK = 0xFFFA_0000_0000_0000u64
const STRING6_MASK = 0x7FFB_0000_0000_0000u64

# TODO: these should be thread-local
var STRINGS*: ManagedStrings = ManagedStrings()
var SYMBOLS*: ManagedSymbols = ManagedSymbols()
var REFS*: ManagedReferences = ManagedReferences()

proc todo*() =
  raise new_exception(Exception, "TODO")

proc new_ref*(v: Reference): int =
  if REFS.free.len == 0:
    REFS.data.add(v)
    return REFS.data.len - 1
  else:
    let i = REFS.free.pop()
    REFS.data[i] = v
    return i

proc free_ref*(i: int) =
  REFS.data[i] = nil
  REFS.free.add(i)

proc new_str*(s: string): int =
  new_ref(Reference(kind: VkString, str: s))
  # if STRINGS.free.len == 0:
  #   STRINGS.data.add(s)
  #   return STRINGS.data.len - 1
  # else:
  #   let i = STRINGS.free.pop()
  #   STRINGS.data[i] = s
  #   return i

proc free_str*(i: int) =
  free_ref(i)
  # STRINGS.data[i] = ""
  # STRINGS.free.add(i)

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
    of STRING_PREFIX, STRING6_PREFIX:
      return VkString
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

# proc to_rune*(v: Value): Rune {.inline.} =
#   todo()

# proc to_value*(v: Rune): Value {.inline.} =
#   cast[Value](bitor(RUNE_MASK, v.ord.uint64))

proc to_value*(v: string): Value {.inline.} =
  case v.len:
    of 0:
      return cast[Value](EMPTY_STRING)
    of 1:
      return cast[Value](bitor(STRING_MASK, 1.shl(40).uint64,
        v[0].ord.uint64))
    of 2:
      return cast[Value](bitor(STRING_MASK, 2.shl(40).uint64,
        v[0].ord.shl(8).uint64, v[1].ord.uint64))
    of 3:
      return cast[Value](bitor(STRING_MASK, 3.shl(40).uint64,
        v[0].ord.shl(16).uint64, v[1].ord.shl(8).uint64, v[2].ord.uint64))
    of 4:
      return cast[Value](bitor(STRING_MASK, 4.shl(40).uint64,
        v[0].ord.shl(24).uint64, v[1].ord.shl(16).uint64, v[2].ord.shl(8).uint64, v[3].ord.uint64))
    of 5:
      return cast[Value](bitor(STRING_MASK, 5.shl(40).uint64,
        v[0].ord.shl(32).uint64, v[1].ord.shl(24).uint64, v[2].ord.shl(16).uint64, v[3].ord.shl(8).uint64, v[4].ord.uint64))
    of 6:
      return cast[Value](bitor(STRING6_MASK,
        v[0].ord.shl(40).uint64, v[1].ord.shl(32).uint64, v[2].ord.shl(24).uint64, v[3].ord.shl(16).uint64, v[4].ord.shl(8).uint64, v[5].ord.uint64))
    else:
      let i = new_str(v).uint64
      return cast[Value](bitor(STRING_MASK, i))

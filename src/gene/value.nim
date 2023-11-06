import re, bitops, strformat

type
  ValueKind* = enum
    # VkVoid vs VkNil vs VkPlaceholder:
    #   VkVoid has special meaning in some places (e.g. templates)
    #   Value(kind: VkNil) and nil should have same meaning and is the default/uninitialized value.
    #   VkPlaceholder can be interpreted any way we want
    VkVoid
    VkNil
    VkPlaceholder
    # VkAny vs VkCustom:
    # VkAny can be used to represent anything
    # VkCustom can be used to represent any value that inherits from CustomValue
    VkAny
    VkPointer
    VkCustom
    VkBool
    VkInt
    VkRatio
    VkFloat
    VkBin
    VkBin64
    VkByte
    VkBytes
    # VkPercent # xx.xx%
    VkChar
    VkString
    VkSymbol
    VkComplexSymbol
    VkRegex
    VkRegexMatch
    VkRange
    VkSelector
    VkQuote
    VkUnquote
    VkReference
    VkRefTarget
    # Time part should be 00:00:00 and timezone should not matter
    VkDate
    # Date + time + timezone
    VkDateTime
    VkTime
    VkTimezone
    VkVector
    VkMap
    VkSet
    VkGene
    VkArguments
    VkStream
    VkDocument
    VkFile
    VkArchiveFile
    VkDirectory
    # Internal types
    VkException = 128
    VkGeneProcessor
    VkApplication
    VkPackage
    VkModule
    VkNamespace
    VkFunction
    VkBoundFunction
    VkMacro
    VkBlock
    VkClass
    VkMixin
    VkMethod
    VkBoundMethod
    VkNativeFn
    VkNativeFn2
    VkNativeMethod
    VkNativeMethod2
    VkInstance
    VkCast
    VkEnum
    VkEnumMember
    # VkInterception
    # VkExpr
    VkExplode
    VkFuture
    VkThread
    VkThreadMessage
    VkJson
    VkNativeFile
    VkCuId
    VkCompilationUnit

  Value* = distinct int64

proc todo*() =
  raise new_exception(Exception, "TODO")

# const NAN_MASK = 0x7FFA000000000000
const I64_MASK = 0xC000000000000000
const F64_ZERO = 0x2000000000000000

const NIL_MASK = 0x7FFA
const NIL* = cast[Value](0x7FFAA00000000000)

const BOOL_MASK = 0x7FFC
const TRUE* = cast[Value](0x7FFCA00000000000)
const FALSE* = cast[Value](0x7FFC000000000000)

const POINTER_MASK = 0x7FFB

const OTHER_MASK = 0x7FFE

const VOID* = cast[Value](0x7FFE000000000000)
const PLACEHOLDER* = cast[Value](0x7FFE010000000000)

# proc is_i64*(v: Value): bool {.inline.} =
#   bitor(cast[int64](v).shl(1), 0x3FFFFFFFFFFFFFFF) == 0x3FFFFFFFFFFFFFFF

# proc is_f64*(v: Value): bool {.inline.} =
#   bitor(cast[int64](v).shl(1), 0x3FFFFFFFFFFFFFFF) != 0x3FFFFFFFFFFFFFFF

# proc to_int*(v: Value): int64 {.inline.} = cast[int64](v)
# proc to_value*(v: int64): Value {.inline.} = cast[Value](v)

proc to_binstr*(v: int): string =
  re.replacef(fmt"{v:064b}", re.re"([01]{8})", "$1 ")

proc `==`*(a, b: Value): bool {.inline.} =
  cast[int64](a) == cast[int64](b)

proc kind*(v: Value): ValueKind {.inline.} =
  let v1 = cast[int64](v)
  case v1.shr(48):
    of NIL_MASK:
      return VkNil
    of BOOL_MASK:
      return VkBool
    of POINTER_MASK:
      return VkPointer
    of OTHER_MASK:
      let other_info = cast[Value](bitand(v1, 0x7FFEFF0000000000))
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

proc to_float*(v: Value): float64 {.inline.} =
  if cast[int64](v) == F64_ZERO:
    return 0.0
  else:
    return cast[float64](v)

proc to_value*(v: float64): Value {.inline.} =
  if v == 0.0:
    return cast[Value](F64_ZERO)
  else:
    return cast[Value](v)

proc to_bool*(v: Value): bool {.inline.} =
  if v == TRUE:
    return true
  let v = cast[int64](v)
  case v.shr(48):
    of NIL_MASK:
      return false
    of BOOL_MASK:
      return false
    else:
      return false

proc to_value*(v: bool): Value {.inline.} =
  if v:
    return TRUE
  else:
    return FALSE

proc to_pointer*(v: Value): pointer {.inline.} =
  cast[pointer](bitand(cast[int64](v), 0x0000FFFFFFFFFFFF))

proc to_value*(v: pointer): Value {.inline.} =
  cast[Value](bitor(cast[int64](v), 0x7FFB000000000000))

import tables

import ./map_key
import ./types

type
  Translator* = proc(v: Value): Value

var Translators*     = Table[ValueKind, Translator]()
var GeneTranslators* = Table[string, Translator]()

proc default_translator(v: Value): Value =
  v
  # case v.kind:
  # of VkNil, VkBool, VkInt, VkString:
  #   return v
  # else:
  #   return v

proc translate*(v: Value): Value =
  var translator = Translators.get_or_default(v.kind, default_translator)
  translator(v)

# proc init_translators() =
#   Translators[VkSymbol] = proc(v: Value): Value =
#     v

# init_translators()

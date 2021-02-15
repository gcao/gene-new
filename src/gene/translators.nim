import tables

import ./map_key
import ./types

type
  Translator* = proc(v: Value): Value

var Translators*     = Table[ValueKind, Translator]()
var GeneTranslators* = Table[string, Translator]()

#################### Definitions #################

proc translate*(stmts: seq[Value]): Value

##################################################

proc default_translator(v: Value): Value =
  case v.kind:
  of VkNil, VkBool, VkInt, VkString:
    return v
  of VkStream:
    return translate(v.stream)
  else:
    return v

proc translate*(v: Value): Value =
  var translator = Translators.get_or_default(v.kind, default_translator)
  translator(v)

proc translate*(stmts: seq[Value]): Value =
  case stmts.len:
  of 0:
    result = Nil
  of 1:
    result = translate(stmts[0])
  else:
    result = Value(kind: VkExGroup)
    for stmt in stmts:
      result.ex_group.add(translate(stmt))

# proc init_translators() =
#   Translators[VkSymbol] = proc(v: Value): Value =
#     v

# init_translators()

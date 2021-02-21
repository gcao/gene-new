import tables

import ./map_key
import ./types

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

proc arg_translator*(v: Value): Value =
  result = Value(kind: VkExArgument)
  for key, value in v.ex_gene_value.gene_props:
    result.ex_arg_props[key] = translate(value)
  for item in v.ex_gene_value.gene_data:
    result.ex_arg_data.add(translate(item))

# proc init_translators() =
#   Translators[VkSymbol] = proc(v: Value): Value =
#     v

# init_translators()

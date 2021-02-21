import tables

import ./map_key
import ./types

var Translators*     = Table[ValueKind, Translator]()
var GeneTranslators* = Table[string, Translator]()

#################### Definitions #################

proc translate*(stmts: seq[Value]): Value

##################################################

proc default_translator(value: Value): Value =
  case value.kind:
  of VkNil, VkBool, VkInt, VkString:
    return value
  of VkStream:
    return translate(value.stream)
  else:
    return value

proc translate*(value: Value): Value =
  var translator = Translators.get_or_default(value.kind, default_translator)
  translator(value)

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

proc arg_translator*(value: Value): Value =
  result = Value(kind: VkExArgument)
  for k, v in value.ex_gene_value.gene_props:
    result.ex_arg_props[k] = translate(v)
  for v in value.ex_gene_value.gene_data:
    result.ex_arg_data.add(translate(v))

# proc init_translators() =
#   Translators[VkSymbol] = proc(value: Value): Value =
#     value

# init_translators()

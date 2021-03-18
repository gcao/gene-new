import tables

import ./map_key
import ./types

var Translators*     = Table[ValueKind, Translator]()
var GeneTranslators* = Table[string, Translator]()

#################### Definitions #################

proc translate*(stmts: seq[Value]): Expr

##################################################

proc default_translator(value: Value): Expr =
  case value.kind:
  of VkNil, VkBool, VkInt, VkString:
    return ExLiteral(data: value)
  of VkStream:
    return translate(value.stream)
  else:
    todo($value.kind)

proc translate*(value: Value): Expr =
  var translator = Translators.get_or_default(value.kind, default_translator)
  translator(value)

proc translate*(stmts: seq[Value]): Expr =
  case stmts.len:
  of 0:
    result = new_ex_literal(Nil)
  of 1:
    result = translate(stmts[0])
  else:
    result = new_ex_group()
    for stmt in stmts:
      cast[ExGroup](result).data.add(translate(stmt))

# proc arg_translator*(value: Value): Value =
#   result = Value(kind: VkExArgument)
#   for k, v in value.ex_gene_value.gene_props:
#     result.ex_arg_props[k] = translate(v)
#   for v in value.ex_gene_value.gene_data:
#     result.ex_arg_data.add(translate(v))

# proc init_translators() =
#   Translators[VkSymbol] = proc(value: Value): Value =
#     value

# init_translators()

import tables

import ./map_key
import ./types
import ./exprs

var Translators*     = Table[ValueKind, Translator]()
var GeneTranslators* = Table[string, Translator]()

#################### Definitions #################

proc translate*(stmts: seq[Value]): Expr

##################################################

proc default_translator(value: Value): Expr =
  case value.kind:
  of VkNil, VkBool, VkInt, VkString:
    return new_ex_literal(value)
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

# (@p = 1)
proc translate_prop_assignment*(value: Value): Expr =
  var name = value.gene_type.symbol[1..^1]
  return new_ex_set_prop(name, translate(value.gene_data[1]))

# (obj .@p)
proc translate_prop_access*(value: Value): Expr =
  var obj = translate(value.gene_type)
  var name = value.gene_data[0].symbol[2..^1]
  return new_ex_get_prop2(obj, name)

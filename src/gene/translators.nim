import tables

import ./types
import ./exprs

#################### Definitions #################

proc translate*(stmts: seq[Value]): Expr

##################################################

proc default_translator(value: Value): Expr =
  case value.kind:
  of VkNil, VkBool, VkInt, VkFloat, VkRegex, VkTime:
    return new_ex_literal(value)
  of VkString:
    return new_ex_string(value)
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

export ExException, new_ex_exception

proc translate_catch*(value: Value): Expr =
  try:
    result = translate(value)
  except system.Exception as e:
    # echo e.msg
    # echo e.get_stack_trace()
    result = new_ex_exception(e)

proc translate_wrap*(translate: Translator): Translator =
  return proc(value: Value): Expr =
    result = translate(value)
    if result != nil and result of ExException:
      raise cast[ExException](result).ex

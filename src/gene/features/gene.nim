import strutils
import tables

import ../map_key
import ../types
import ../exprs
import ../normalizers
import ../translators
import ./core
import ./arithmetic
import ./regex
import ./selector
import ./native
import ./range
import ./oop

proc arg_translator*(value: Value): Expr =
  return translate_arguments(value)

proc default_invoker(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  result = new_gene_gene(target)
  var expr = cast[ExArguments](expr)
  for k, v in expr.props.mpairs:
    result.gene_props[k] = self.eval(frame, v)
  for v in expr.children.mitems:
    var r = self.eval(frame, v)
    if r.kind == VkExplode:
      for item in r.explode.vec:
        result.gene_children.add(item)
    else:
      result.gene_children.add(r)

proc eval_gene*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExGene](expr)
  var `type` = self.eval(frame, e.`type`)
  var translator: Translator
  case `type`.kind:
  of VkFunction:
    translator = `type`.fn.translator
  of VkBoundFunction:
    translator = `type`.bound_fn.translator
  of VkMacro:
    translator = `type`.macro.translator
  of VkBlock:
    translator = `type`.block.translator
  of VkSelector:
    translator = `type`.selector.translator
  of VkGeneProcessor:
    translator = `type`.gene_processor.translator
  of VkNativeFn, VkNativeFn2:
    translator = native_fn_arg_translator
  of VkNativeMethod, VkNativeMethod2:
    translator = native_method_arg_translator
  of VkInstance:
    e.args_expr = ExInvoke(
      evaluator: eval_invoke,
      self: e.`type`,
      meth: CALL_KEY,
      args: new_ex_arg(e.args),
    )
    return self.eval_invoke(frame, `type`, e.args_expr)
  else:
    e.args_expr = arg_translator(e.args)
    return default_invoker(self, frame, `type`, e.args_expr)

  e.args_expr = translator(e.args)
  return e.args_expr.evaluator(self, frame, `type`, e.args_expr)

proc default_translator(value: Value): Expr =
  ExGene(
    evaluator: eval_gene,
    `type`: translate(value.gene_type),
    args: value,
  )

proc translate_gene_default(value: Value): Expr {.inline.} =
  ExGene(
    evaluator: eval_gene,
    `type`: translate(value.gene_type),
    args: value,
  )

proc translate_gene(value: Value): Expr =
  var `type` = value.gene_type
  case `type`.kind:
  of VkSymbol:
    case `type`.str:
    of ".":
      value.gene_props[SELF_KEY] = new_gene_symbol("self")
      value.gene_props[METHOD_KEY] = value.gene_children[0]
      value.gene_children.delete 0
      value.gene_type = new_gene_symbol("$invoke_dynamic")
    of "...":
      discard
    else:
      if `type`.str.starts_with(".@"): # (.@x)
        if `type`.str.len == 2:
          return translate_invoke_selector3(value)
        else:
          return translate_invoke_selector4(value)
      elif `type`.str.starts_with("."): # (.method x y z)
        value.gene_props[SELF_KEY] = new_gene_symbol("self")
        value.gene_props[METHOD_KEY] = new_gene_string_move(`type`.str.substr(1))
        value.gene_type = new_gene_symbol("$invoke_method")
  of VkComplexSymbol:
    if `type`.csymbol[0].starts_with(".@"):
      return translate_invoke_selector4(value)
  else:
    discard

  if value.gene_children.len >= 1:
    var first = value.gene_children[0]
    case first.kind:
    of VkSymbol:
      case first.str:
      of ".": # (x . method ...) or (x . function ...)
        value.gene_props[SELF_KEY] = value.gene_type
        value.gene_children.delete 0
        value.gene_props[METHOD_KEY] = value.gene_children[0]
        value.gene_children.delete 0
        value.gene_type = new_gene_symbol("$invoke_dynamic")
      of "==", "!=", "<", "<=", ">", ">=":
        var data = value.gene_children
        data.insert(value.gene_type)
        return translate_comparisons(data)
      of "&&", "||":
        var data = value.gene_children
        data.insert(value.gene_type)
        return translate_logic(data)
      of "=~", "!~":
        return translate_match(value)
      of "+", "-", "*", "/", "**":
        var data = value.gene_children
        data.insert(value.gene_type)
        return translate_arithmetic(data)
      of "..":
        return new_ex_range(translate(`type`), translate(value.gene_children[1]))
      of "=":
        if `type`.kind == VkSymbol and `type`.str.startsWith("@"): # (@p = 1)
          return translate_prop_assignment(value)
      else:
        if first.str.startsWith(".@"):
          if first.str.len == 2:
            return translate_invoke_selector(value)
          else:
            return translate_invoke_selector2(value)
        elif first.str.startsWith("."):
          value.gene_props[SELF_KEY] = `type`
          value.gene_props[METHOD_KEY] = new_gene_string_move(first.str.substr(1))
          value.gene_children.delete 0
          value.gene_type = new_gene_symbol("$invoke_method")
    of VkComplexSymbol:
      if first.csymbol[0].startsWith(".@"):
        return translate_invoke_selector2(value)
    else:
      discard

  value.normalize()

  case value.gene_type.kind:
  of VkSymbol:
    var translator = GeneTranslators.get_or_default(value.gene_type.str, default_translator)
    return translator(value)
  of VkString:
    return translate_string(value)
  of VkFunction:
    # TODO: this can be optimized further
    return ExGene(
      evaluator: eval_gene,
      `type`: new_ex_literal(value.gene_type),
      args: value,
    )
  else:
    return ExGene(
      evaluator: eval_gene,
      `type`: translate(value.gene_type),
      args: value,
    )

proc init*() =
  Translators[VkGene] = translate_gene

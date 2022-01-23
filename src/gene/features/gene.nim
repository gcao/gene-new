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
    result.gene_children.add(self.eval(frame, v))

proc eval_gene(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var `type` = self.eval(frame, cast[ExGene](expr).`type`)
  default_invoker(self, frame, `type`, cast[ExGene](expr).args_expr)

proc eval_gene2(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var `type` = self.eval(frame, cast[ExGene](expr).`type`)
  cast[ExGene](expr).args_expr.evaluator(self, frame, `type`, cast[ExGene](expr).args_expr)

proc eval_gene_init*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExGene](expr)
  var `type` = self.eval(frame, e.`type`)
  var translator: Translator
  case `type`.kind:
  of VkFunction:
    translator = `type`.fn.translator
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
    # For future invocations
    expr.evaluator = eval_gene2
    return self.eval_invoke(frame, `type`, e.args_expr)
  else:
    e.args_expr = arg_translator(e.args)
    # For future invocations
    expr.evaluator = eval_gene
    return default_invoker(self, frame, `type`, e.args_expr)

  e.args_expr = translator(e.args)
  expr.evaluator = eval_gene2
  return e.args_expr.evaluator(self, frame, `type`, e.args_expr)

proc default_translator(value: Value): Expr =
  ExGene(
    evaluator: eval_gene_init,
    `type`: translate(value.gene_type),
    args: value,
  )

proc translate_gene(value: Value): Expr =
  # normalize is inefficient.
  if value.gene_type.kind == VkSymbol and value.gene_type.symbol.starts_with(".@"):
    if value.gene_type.symbol.len == 2:
      return translate_invoke_selector3(value)
    else:
      return translate_invoke_selector4(value)
  elif value.gene_type.kind == VkSymbol and value.gene_type.symbol == "import":
    discard
  elif value.gene_type.kind == VkComplexSymbol and value.gene_type.csymbol[0].starts_with(".@"):
    return translate_invoke_selector4(value)
  elif value.gene_children.len >= 1:
    var `type` = value.gene_type
    var first = value.gene_children[0]
    case first.kind:
    of VkSymbol:
      if COMPARISON_OPS.contains(first.symbol):
        value.gene_children.insert(value.gene_type)
        value.gene_type = nil
        return translate_comparisons(value.gene_children)
      elif LOGIC_OPS.contains(first.symbol):
        value.gene_children.insert(value.gene_type)
        value.gene_type = nil
        return translate_logic(value.gene_children)
      elif REGEX_OPS.contains(first.symbol):
        return translate_match(value)
      elif arithmetic.BINARY_OPS.contains(first.symbol):
        value.gene_children.insert(value.gene_type)
        value.gene_type = nil
        return translate_arithmetic(value.gene_children)
      elif first.symbol == "=" and `type`.kind == VkSymbol and `type`.symbol.startsWith("@"): # (@p = 1)
        return translate_prop_assignment(value)
      elif first.symbol == "..":
        return new_ex_range(translate(`type`), translate(value.gene_children[1]))
      elif first.symbol.startsWith(".@"):
        if first.symbol.len == 2:
          return translate_invoke_selector(value)
        else:
          return translate_invoke_selector2(value)
    of VkComplexSymbol:
      if first.csymbol[0].startsWith(".@"):
        return translate_invoke_selector2(value)
    else:
      discard

  value.normalize()

  case value.gene_type.kind:
  of VkSymbol:
    var translator = GeneTranslators.get_or_default(value.gene_type.symbol, default_translator)
    return translator(value)
  of VkString:
    return translate_string(value)
  of VkFunction:
    # TODO: this can be optimized further
    return ExGene(
      evaluator: eval_gene_init,
      `type`: new_ex_literal(value.gene_type),
      args: value,
    )
  else:
    return ExGene(
      evaluator: eval_gene_init,
      `type`: translate(value.gene_type),
      args: value,
    )

proc init*() =
  Translators[VkGene] = translate_gene

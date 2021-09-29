import strutils
import tables

import ../map_key
import ../types
import ../exprs
import ../normalizers
import ../translators
import ./selectors

proc arg_translator*(value: Value): Expr =
  var e = new_ex_arg()
  for k, v in value.gene_props:
    e.props[k] = translate(v)
  for v in value.gene_data:
    e.data.add(translate(v))
  return e

proc default_invoker(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  result = new_gene_gene(target)
  var expr = cast[ExArguments](expr)
  for k, v in expr.props.mpairs:
    result.gene_props[k] = self.eval(frame, v)
  for v in expr.data.mitems:
    result.gene_data.add(self.eval(frame, v))

proc eval_gene(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var `type` = self.eval(frame, cast[ExGene](expr).`type`)
  default_invoker(self, frame, `type`, cast[ExGene](expr).args_expr)

proc eval_gene2(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var `type` = self.eval(frame, cast[ExGene](expr).`type`)
  cast[ExGene](expr).args_expr.evaluator(self, frame, `type`, cast[ExGene](expr).args_expr)

proc eval_gene_init(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
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
  if value.gene_data.len >= 1:
    var `type` = value.gene_type
    var first = value.gene_data[0]
    if first.kind == VkSymbol:
      # (@p = 1)
      if first.symbol == "=" and `type`.kind == VkSymbol and `type`.symbol.startsWith("@"):
        return translate_prop_assignment(value)
      elif first.symbol.startsWith(".@"):
        if first.symbol.len > 2:
          return translate_prop_access(value)
        else:
          todo()

  value.normalize()

  case value.gene_type.kind:
  of VkSymbol:
    var translator = GeneTranslators.get_or_default(value.gene_type.symbol, default_translator)
    return translator(value)
  of VkFunction:
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

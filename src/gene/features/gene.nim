import tables

import ../map_key
import ../types
import ../exprs
import ../normalizers
import ../translators
import ../interpreter

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

proc init*() =
  Translators[VkGene] = proc(value: Value): Expr =
    value.normalize()
    case value.gene_type.kind:
    of VkSymbol:
      var translator = GeneTranslators.get_or_default(value.gene_type.symbol, default_translator)
      return translator(value)
    else:
      return ExGene(
        evaluator: eval_gene_init,
        `type`: translate(value.gene_type),
        args: value,
      )

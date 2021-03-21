import tables

import ../map_key
import ../types
import ../normalizers
import ../translators
import ../interpreter

type
  ExGene* = ref object of Expr
    `type`*: Expr
    input*: Value   # The unprocessed input
    processor*: GeneProcessor

  ExArgument* = ref object of Expr
    props*: Table[MapKey, Value]
    data*: seq[Value]

proc should_translate_args(`type`: Value): bool =
  true

proc default_invoker(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  result = new_gene_gene(target)
  # var e = cast[ExGene](expr)
  # for k, v in e.args.mpairs:
  #   result.gene_props[k] = self.eval(frame, v)
  # for v in expr.ex_arg_data.mitems:
  #   result.gene_data.add(self.eval(frame, v))

proc invoker(`type`: Value): Invoker =
  case `type`.kind:
  of VkFunction:
    function_invoker
  else:
    default_invoker

# proc translate_args(value: Value): Expr =
#   todo()

# proc default_translator(value: Value): Expr =
#   ExGene(
#     `type`: translate(value.gene_type),
#     value: value,
#   )

# var DEFAULT_EXTENSION = GeneExtension(
#   translator: translate_args,
#   invoker: default_invoker,
# )

proc eval_gene(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var e = cast[ExGene](expr)
  var `type` = self.eval(frame, e.`type`)
  if `type`.should_translate_args():
    todo()
  invoker(`type`)(self, frame, `type`, expr)

  # if e.extension == nil:
  #   e.extension = Extensions.get_or_default(`type`.kind, DEFAULT_EXTENSION)
  #   expr.ex_gene_value = expr.ex_gene_extension.translator(expr)

  # expr.ex_gene_extension.invoker(self, frame, `type`, expr.ex_gene_value)

proc eval_gene2(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  todo()

# proc eval_args(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
#   result = Value(kind: VkGene)
#   for k, v in expr.ex_arg_props.mpairs:
#     result.gene_props[k] = self.eval(frame, v)
#   for v in expr.ex_arg_data.mitems:
#     result.gene_data.add(self.eval(frame, v))

proc init*() =
  Translators[VkGene] = proc(value: Value): Expr =
    value.normalize()
    ExGene(
      evaluator: eval_gene,
      `type`: translate(value.gene_type),
    )
    # case value.gene_type.kind:
    # of VkSymbol:
    #   var translator = GeneTranslators.get_or_default(value.gene_type.symbol, default_translator)
    #   translator(value)
    # else:
    #   ExGene(
    #     evaluator: eval_gene,
    #     `type`: translate(value.gene_type),
    #     # args: value,
    #   )

  # Evaluators[VkExGene.ord] = gene_evaluator
  # Evaluators[VkExArgument.ord] = arg_evaluator

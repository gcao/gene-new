import tables

import ../types
import ../normalizers
import ../translators
import ../interpreter

proc default_translator(value: Value): Value =
  Value(
    kind: VkExGene,
    ex_gene_type: translate(value.gene_type),
    ex_gene_value: value,
  )

proc default_invoker(self: VirtualMachine, frame: Frame, target: Value, expr: Value): Value =
  result = new_gene_gene(target)
  for k, v in expr.ex_arg_props:
    result.gene_props[k] = self.eval(frame, v)
  for v in expr.ex_arg_data:
    result.gene_data.add(self.eval(frame, v))

var DEFAULT_EXTENSION = GeneExtension(
  translator: arg_translator,
  invoker: default_invoker,
)

proc init*() =
  Translators[VkGene] = proc(value: Value): Value =
    value.normalize()
    case value.gene_type.kind:
    of VkSymbol:
      var translator = GeneTranslators.get_or_default(value.gene_type.symbol, default_translator)
      translator(value)
    else:
      Value(
        kind: VkExGene,
        ex_gene_type: translate(value.gene_type),
        ex_gene_value: value,
      )

  proc gene_evaluator(self: VirtualMachine, frame: Frame, expr: Value): Value =
    var `type` = self.eval(frame, expr.ex_gene_type)
    if expr.ex_gene_extension == nil:
      expr.ex_gene_extension = Extensions.get_or_default(`type`.kind, DEFAULT_EXTENSION)
      expr.ex_gene_value = expr.ex_gene_extension.translator(expr)

    expr.ex_gene_extension.invoker(self, frame, `type`, expr.ex_gene_value)

  proc arg_evaluator(self: VirtualMachine, frame: Frame, expr: Value): Value =
    result = Value(kind: VkGene)
    for k, v in expr.ex_arg_props:
      result.gene_props[k] = self.eval(frame, v)
    for v in expr.ex_arg_data:
      result.gene_data.add(self.eval(frame, v))

  Evaluators[VkExGene] = gene_evaluator
  Evaluators[VkExArgument] = arg_evaluator

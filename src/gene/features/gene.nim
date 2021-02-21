import tables

import ../types
import ../normalizers
import ../translators
import ../interpreter

proc default_translator(v: Value): Value =
  Value(
    kind: VkExGene,
    ex_gene_type: translate(v.gene_type),
    ex_gene_value: v,
  )

proc default_invoker(self: VirtualMachine, frame: Frame, target: Value, expr: Value): Value =
  result = new_gene_gene(target)
  for k, v in expr.gene_props:
    result.gene_props[k] = self.eval(frame, v)
  for v in expr.gene_data:
    result.gene_data.add(self.eval(frame, v))

var DEFAULT_EXTENSION = GeneExtension(
  translator: arg_translator,
  invoker: default_invoker,
)

proc init*() =
  Translators[VkGene] = proc(v: Value): Value =
    v.normalize()
    case v.gene_type.kind:
    of VkSymbol:
      var translator = GeneTranslators.get_or_default(v.gene_type.symbol, default_translator)
      translator(v)
    else:
      Value(
        kind: VkExGene,
        ex_gene_type: translate(v.gene_type),
        ex_gene_value: v,
      )

  Evaluators[VkExGene] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    var `type` = self.eval(frame, expr.ex_gene_type)
    if expr.ex_gene_invoker == nil:
      var extension = Extensions.get_or_default(`type`.kind, DEFAULT_EXTENSION)
      expr.ex_gene_value = extension.translator(expr)
      expr.ex_gene_invoker = extension.invoker

    var args = self.eval(frame, expr.ex_gene_value)
    expr.ex_gene_invoker(self, frame, `type`, args)

  Evaluators[VkExArgument] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    result = Value(kind: VkGene)
    for k, v in expr.ex_arg_props:
      result.gene_props[k] = self.eval(frame, v)
    for item in expr.ex_arg_data:
      result.gene_data.add(self.eval(frame, item))


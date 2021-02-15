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
    result.gene_props[k] = self.eval(frame, translate(v))
  for v in expr.gene_data:
    result.gene_data.add(self.eval(frame, translate(v)))

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
      expr.ex_gene_invoker = Invokers.get_or_default(`type`.kind, default_invoker)
    expr.ex_gene_invoker(self, frame, `type`, expr.ex_gene_value)

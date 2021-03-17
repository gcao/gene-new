import tables

import ../map_key
import ../types
import ../translators
import ../interpreter

proc init*() =
  Translators[VkSymbol] = proc(value: Value): Value =
    result = Value(
      kind: VkExSymbol,
      ex_symbol: value.symbol.to_key,
    )

  proc symbol_evaluator(self: VirtualMachine, frame: Frame, expr: var Value): Value =
    case expr.ex_symbol_kind:
    of SkUnknown:
      if frame.scope.has_key(expr.ex_symbol):
        expr.ex_symbol_kind = SkScope
        result = frame.scope[expr.ex_symbol]
      else:
        expr.ex_symbol_kind = SkNamespace
        result = frame.ns[expr.ex_symbol]
    of SkScope:
      result = frame.scope[expr.ex_symbol]
    of SkNamespace:
      result = frame.ns[expr.ex_symbol]
    else:
      todo()

  GeneTranslators["var"] = proc(value: Value): Value =
    var name = value.gene_data[0]
    var v: Value
    if value.gene_data.len > 1:
      v = translate(value.gene_data[1])
    else:
      v = Nil
    case name.kind:
    of VkSymbol:
      result = Value(
        kind: VkExVar,
        ex_var_name: name.symbol.to_key,
        ex_var_value: v,
      )
    else:
      todo($name.kind)

  proc var_evaluator(self: VirtualMachine, frame: Frame, expr: var Value): Value =
    var value = self.eval(frame, expr.ex_var_value)
    frame.scope.def_member(expr.ex_var_name, value)

  Evaluators[VkExSymbol.ord] = symbol_evaluator
  Evaluators[VkExVar.ord] = var_evaluator

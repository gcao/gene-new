import tables

import ../map_key
import ../types
import ../translators
import ../interpreter

proc init*() =
  Translators[VkSymbol] = proc(v: Value): Value =
    result = Value(
      kind: VkExSymbol,
      ex_symbol: v.symbol.to_key,
    )

  Evaluators[VkExSymbol] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    result = frame.scope[expr.ex_symbol]

  GeneTranslators["var"] = proc(v: Value): Value =
    var name = v.gene_data[0]
    var value: Value
    if v.gene_data.len > 1:
      value = translate(v.gene_data[1])
    else:
      value = Nil
    case name.kind:
    of VkSymbol:
      result = Value(
        kind: VkExVar,
        ex_var_name: name.symbol.to_key,
        ex_var_value: value,
      )
    else:
      todo($name.kind)

  Evaluators[VkExVar] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    var value = self.eval(frame, expr.ex_var_value)
    frame.scope.def_member(expr.ex_var_name, value)

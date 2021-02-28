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

  Evaluators[VkExSymbol] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    result = frame[expr.ex_symbol]

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

  Evaluators[VkExVar] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    var value = self.eval(frame, expr.ex_var_value)
    frame.d.scope.def_member(expr.ex_var_name, value)

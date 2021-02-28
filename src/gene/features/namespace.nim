import tables

import ../types
import ../translators
import ../interpreter

proc init*() =
  GeneTranslators["ns"] = proc(value: Value): Value =
    Value(
      kind: VkExNamespace,
      ex_ns_name: value.gene_data[0].symbol,
    )

  Evaluators[VkExNamespace.ord] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    var ns = new_namespace(expr.ex_ns_name)
    result = Value(kind: VkNamespace, ns: ns)
    frame.ns[expr.ex_ns_name] = result

  Evaluators[VkExNsDef.ord] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    result = self.eval(frame, expr.ex_ns_def_value)
    frame.ns[expr.ex_ns_def_name] = result

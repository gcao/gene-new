import tables

import ../types
import ../translators
import ../interpreter

proc init*() =
  GeneTranslators["ns"] = proc(v: Value): Value =
    Value(
      kind: VkExNamespace,
      ex_ns_name: v.gene_data[0].symbol,
    )

  Evaluators[VkExNamespace] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    var ns = new_namespace(expr.ex_ns_name)
    result = Value(kind: VkNamespace, ns: ns)
    frame.ns[expr.ex_ns_name] = result

  Evaluators[VkExNsDef] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    result = self.eval(frame, expr.ex_ns_def_value)
    frame.ns[expr.ex_ns_def_name] = result

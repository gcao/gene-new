import tables

# import ../map_key
import ../types
import ../translators
# import ../interpreter

type
  ExNamespace* = ref object of Expr
    name*: string
    body*: Expr

proc eval_ns(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var ns = new_namespace(cast[ExNamespace](expr).name)
  result = Value(kind: VkNamespace, ns: ns)
  frame.ns[cast[ExNamespace](expr).name] = result

proc init*() =
  GeneTranslators["ns"] = proc(value: Value): Expr =
    ExNamespace(
      evaluator: eval_ns,
      name: value.gene_data[0].symbol,
    )

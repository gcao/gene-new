import tables

# import ../map_key
import ../types
import ../translators
import ../interpreter

type
  ExNamespace* = ref object of Expr
    name*: string
    body*: Expr

proc eval_ns(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var ns = new_namespace(cast[ExNamespace](expr).name)
  ns.parent = frame.ns
  result = Value(kind: VkNamespace, ns: ns)
  frame.ns[cast[ExNamespace](expr).name] = result
  var old_self = frame.self
  var old_ns = frame.ns
  try:
    frame.self = result
    frame.ns = ns
    discard self.eval(frame, cast[ExNamespace](expr).body)
  finally:
    frame.self = old_self
    frame.ns = old_ns

proc init*() =
  GeneTranslators["ns"] = proc(value: Value): Expr =
    ExNamespace(
      evaluator: eval_ns,
      name: value.gene_data[0].symbol,
      body: translate(value.gene_data[1..^1]),
    )

import tables

# import ../map_key
import ../types
import ../translators
# import ../interpreter

type
  ExClass* = ref object of Expr
    name*: string
    body*: Expr

proc eval_class(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var class = new_class(cast[ExClass](expr).name)
  class.ns.parent = frame.ns
  result = Value(kind: VkClass, class: class)
  frame.ns[cast[ExClass](expr).name] = result

proc translate_class(value: Value): Expr =
  ExClass(
    evaluator: eval_class,
    name: value.gene_data[0].symbol,
    body: translate(value.gene_data[1..^1]),
  )

proc init*() =
  GeneTranslators["class"] = translate_class

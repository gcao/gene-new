import tables

# import ../map_key
import ../types
import ../translators
import ../interpreter

type
  ExClass* = ref object of Expr
    name*: string
    body*: Expr

  ExNew* = ref object of Expr
    class*: Expr
    args*: Expr

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

proc eval_new(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var instance = Instance()
  instance.class = self.eval(frame, cast[ExNew](expr).class).class
  result = Value(
    kind: VkInstance,
    instance: instance,
  )

proc translate_new(value: Value): Expr =
  ExNew(
    evaluator: eval_new,
    class: translate(value.gene_data[0]),
  )

proc init*() =
  GeneTranslators["class"] = translate_class
  GeneTranslators["new"] = translate_new

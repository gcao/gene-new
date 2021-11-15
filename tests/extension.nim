import tables

import gene/types
import gene/translators
include gene/ext_common

type
  ExTest = ref object of Expr
    data: Expr

var MyClass: Value

proc eval_test(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExTest](expr)
  self.eval_catch(frame, expr.data)

proc translate_test(value: Value): Expr =
  return ExTest(
    evaluator: eval_test,
    data: translate(value.gene_data[0]),
  )

{.push dynlib exportc.}

proc test*(self: Value): Value =
  self.gene_data[0]

proc init*() =
  GeneTranslators["test"] = translate_test
  MyClass = Value(
    kind: VkClass,
    class: new_class("MyClass"),
  )
  MyClass.class.parent = ObjectClass.class
  GLOBAL_NS.ns["MyClass"] = MyClass

{.pop.}

import tables

import gene/types
import gene/translators
include gene/ext_common

type
  TestValue = ref object of CustomValue
    i: int
    s: string

  ExTest = ref object of Expr
    data: Expr

var TestClass: Value

proc eval_test(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExTest](expr)
  self.eval_catch(frame, expr.data)

proc translate_test(value: Value): Expr =
  return ExTest(
    evaluator: eval_test,
    data: translate(value.gene_data[0]),
  )

proc new_test*(args: Value): Value {.nimcall.} =
  try:
    result = Value(
      kind: VkCustom,
      custom_class: TestClass.class,
      custom: TestValue(
        i: args.gene_data[0].int,
        s: args.gene_data[1].str,
      ),
    )
  except CatchableError as e:
    var s = "Exception: " & e.msg & "\n" & e.get_stack_trace()
    echo s
    result = Value(
      kind: VkException,
      exception: e,
    )

proc test_i*(args: Value): Value {.nimcall.} =
  TestValue(args.gene_data[0].custom).i

proc test_i*(self: Value, args: Value): Value {.nimcall.} =
  TestValue(self.custom).i

{.push dynlib exportc.}

proc test*(self: Value): Value =
  self.gene_data[0]

proc init*() =
  try:
    GeneTranslators["test"] = translate_test

    GLOBAL_NS.ns["new_test"] = Value(kind: VkNativeFn, native_fn: new_test)
    GLOBAL_NS.ns["test_i"]   = Value(kind: VkNativeFn, native_fn: test_i)

    TestClass = Value(
      kind: VkClass,
      class: new_class("TestClass"),
    )
    TestClass.class.parent = ObjectClass.class
    GLOBAL_NS.ns["TestClass"] = TestClass
    TestClass.def_native_method("i", test_i)
  except system.Exception as e:
    echo e.msg
    echo e.get_stack_trace()

{.pop.}

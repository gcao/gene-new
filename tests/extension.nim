include gene/ext_common

type
  Extension = ref object of CustomValue
    i: int
    s: string

  ExTest = ref object of Expr
    data: Expr

var ExtensionClass: Value

proc eval_test(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExTest](expr)
  self.eval(frame, expr.data)

proc translate_test(value: Value): Expr {.nimcall, wrap_exception.} =
  return ExTest(
    evaluator: eval_wrap(eval_test),
    data: translate(value.gene_data[0]),
  )

proc new_extension*(args: Value): Value {.nimcall, wrap_exception.} =
  Value(
    kind: VkCustom,
    custom_class: ExtensionClass.class,
    custom: Extension(
      i: args.gene_data[0].int,
      s: args.gene_data[1].str,
    ),
  )

proc get_i*(args: Value): Value {.nimcall, wrap_exception.} =
  Extension(args.gene_data[0].custom).i

proc get_i*(self: Value, args: Value): Value {.nimcall, wrap_exception.} =
  Extension(self.custom).i

{.push dynlib exportc.}

proc init*(): Value {.nimcall, wrap_exception.} =
  GeneTranslators["test"] = translate_wrap(translate_test)

  result = new_namespace()
  result.ns["new_extension"] = new_extension
  result.ns["get_i"] = NativeFn(get_i)

  ExtensionClass = Value(
    kind: VkClass,
    class: new_class("Extension"),
  )
  result.ns["Extension"] = ExtensionClass
  ExtensionClass.class.parent = ObjectClass.class
  ExtensionClass.def_native_constructor(new_extension)
  ExtensionClass.def_native_method("i", get_i)

{.pop.}

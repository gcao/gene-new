import ../types
import ../interpreter_base

proc eval_native_fn(self: VirtualMachine, frame: Frame, expr: var Expr): Value {.gcsafe.} =
  var args = self.eval_args(frame, expr)
  var target = frame.callable
  case target.kind:
  of VkNativeFn:
    return target.native_fn(args)
  of VkNativeFn2:
    return target.native_fn2(args)
  else:
    todo("eval_native_fn " & $target.kind)

proc native_fn_arg_translator*(value: Value): Expr {.gcsafe.} =
  return translate_arguments(value, eval_native_fn)

proc eval_native_method(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var args = self.eval_args(frame, expr)
  var target = frame.callable
  target.native_method(frame.self, args)

proc native_method_arg_translator*(value: Value): Expr {.gcsafe.} =
  return translate_arguments(value, eval_native_method)

proc init*() =
  discard

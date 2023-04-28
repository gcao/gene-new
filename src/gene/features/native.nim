import ../types
import ../interpreter_base

# proc eval_native_fn(frame: Frame, expr: var Expr): Value {.gcsafe.} =
#   var args = eval_args(frame, expr)
#   var target = frame.callable
#   case target.kind:
#   of VkNativeFn:
#     return target.native_fn(args)
#   of VkNativeFn2:
#     return target.native_fn2(args)
#   else:
#     todo("eval_native_fn " & $target.kind)

# proc native_fn_arg_translator*(value: Value): Expr {.gcsafe.} =
#   return translate_arguments(value, eval_native_fn)

proc eval_native_method(frame: Frame, expr: var Expr): Value =
  var args = eval_args(frame, expr)
  var target = frame.callable
  target.native_method(frame, frame.self, args)

proc native_method_arg_translator*(value: Value): Expr {.gcsafe.} =
  return translate_arguments(value, eval_native_method)

proc init*() =
  discard

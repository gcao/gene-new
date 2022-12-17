import gene/types
import gene/interpreter_base except call

var eval_catch*: EvalCatch
var eval_wrap*: EvalWrap
var translate_catch*: TranslateCatch
var translate_wrap*: TranslateWrap
var invoke_catch*: Invoke
var invoke_wrap*: InvokeWrap
var fn_wrap*: NativeFnWrap
var method_wrap*: NativeMethodWrap

proc eval*(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  result = self.eval_catch(frame, expr)
  if result != nil and result.kind == VkException:
    raise result.exception

proc translate*(value: Value): Expr {.gcsafe.} =
  result = translate_catch(value)
  if result != nil and result of ExException:
    raise cast[ExException](result).ex

proc call*(self: VirtualMachine, frame: Frame, target: Value, args: Value): Value =
  result = self.invoke_catch(frame, target, args)
  if result != nil and result.kind == VkException:
    raise result.exception

converter to_value*(v: Namespace): Value =
  Value(kind: VkNamespace, ns: v)

converter to_value*(v: NativeFn): Value =
  Value(
    kind: VkNativeFn2,
    native_fn2: fn_wrap(v),
  )

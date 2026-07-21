# import gene/types
# import gene/interpreter_base except call

# var eval_catch*       {.threadvar.}: EvalCatch
# var eval_wrap*        {.threadvar.}: EvalWrap
# var translate_catch*  {.threadvar.}: TranslateCatch
# var translate_wrap*   {.threadvar.}: TranslateWrap
# var invoke_catch*     {.threadvar.}: Invoke
# var invoke_wrap*      {.threadvar.}: InvokeWrap
# var fn_wrap*          {.threadvar.}: NativeFnWrap
# var method_wrap*      {.threadvar.}: NativeMethodWrap

# proc eval*(frame: Frame, expr: var Expr): Value =
#   result = eval_catch(frame, expr)
#   if result != nil and result.kind == VkException:
#     raise result.exception

# proc translate*(value: Value): Expr {.gcsafe.} =
#   result = translate_catch(value)
#   if result != nil and result of ExException:
#     raise cast[ExException](result).ex

# proc call*(frame: Frame, target: Value, args: Value): Value =
#   result = invoke_catch(frame, target, args)
#   if result != nil and result.kind == VkException:
#     raise result.exception

# converter to_value*(v: Namespace): Value =
#   Value(kind: VkNamespace, ns: v)

# converter to_value*(v: NativeFn): Value =
#   Value(
#     kind: VkNativeFn2,
#     native_fn2: fn_wrap(v),
#   )

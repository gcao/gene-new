# import asyncdispatch

# import gene/types except eval_wrap, translate_catch, translate_wrap, fn_wrap, method_catch, method_wrap
# import gene/interpreter_base except eval, eval_catch, translate, translate_catch, translate_wrap
# import gene/extension/base

# # All extensions should include this module like below
# # include gene/extension/boilerplate
# # `set_globals` will be called when the extension is loaded.

# proc set_globals*(
#   g_disp          : PDispatcher,
#   vm              : VirtualMachine,
#   ecatch          : EvalCatch,
#   ewrap           : EvalWrap,
#   tcatch          : TranslateCatch,
#   twrap           : TranslateWrap,
#   icatch          : Invoke,
#   iwrap           : InvokeWrap,
#   fwrap           : NativeFnWrap,
#   mwrap           : NativeMethodWrap,
# ) {.dynlib exportc.} =
#   set_global_dispatcher(g_disp)
#   VM              = vm
#   eval_catch      = ecatch
#   eval_wrap       = ewrap
#   translate_catch = tcatch
#   translate_wrap  = twrap
#   invoke_catch    = icatch
#   invoke_wrap     = iwrap
#   fn_wrap         = fwrap
#   method_wrap     = mwrap

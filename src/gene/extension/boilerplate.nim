import tables
import asyncdispatch

import gene/map_key
import gene/types except eval, eval_catch, eval_wrap, translate_catch, translate_wrap, fn_wrap, method_catch, method_wrap
import gene/interpreter_base except translate, translate_catch, translate_wrap
import gene/extension/base

# All extensions should include this module like below
# include gene/extension/boilerplate
# `set_globals` will be called when the extension is loaded.

proc set_globals*(
  g_disp          : PDispatcher,
  m               : Mapping,
  translators     : TableRef[ValueKind, Translator],
  gene_translators: TableRef[string, Translator],
  vm              : VirtualMachine,
  ecatch          : EvalCatch,
  ewrap           : EvalWrap,
  tcatch          : TranslateCatch,
  twrap           : TranslateWrap,
  icatch          : Invoke,
  iwrap           : InvokeWrap,
  fwrap           : NativeFnWrap,
  mwrap           : NativeMethodWrap,
) {.dynlib exportc.} =
  set_global_dispatcher(g_disp)
  mapping         = m
  Translators     = translators
  GeneTranslators = gene_translators
  VM              = vm
  eval_catch      = ecatch
  eval_wrap       = ewrap
  translate_catch = tcatch
  translate_wrap  = twrap
  invoke_catch    = icatch
  invoke_wrap     = iwrap
  fn_wrap         = fwrap
  method_wrap     = mwrap

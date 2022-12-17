import dynlib, tables
import asyncdispatch

import ./types
import ./interpreter_base

# Design:
# * Exception handling
#   Pass a wrapper proc to the dynamic lib to eval and catch any exception thrown.
#   Similar logic has to be applied when extension is called from main app.
#
# Resources:
# https://gradha.github.io/articles/2015/01/writing-c-libraries-with-nim.html

type
  Init = proc(module: Module): Value {.nimcall.}

  SetGlobals = proc(
    g_disp          : PDispatcher,
    translators     : TableRef[ValueKind, Translator],
    gene_translators: TableRef[string, Translator],
    vm              : VirtualMachine,
    eval_catch      : EvalCatch,
    eval_wrap       : EvalWrap,
    translate_catch : TranslateCatch,
    translate_wrap  : TranslateWrap,
    invoke_catch    : Invoke,
    invoke_wrap     : InvokeWrap,
    fn_wrap         : NativeFnWrap,
    method_wrap     : NativeMethodWrap,
  ) {.nimcall.}

proc call_set_globals(p: pointer)

# TODO: unload dynamic libraries before reloading

proc load_dynlib*(pkg: Package, path: string): Module =
  result = new_module(pkg, path)
  var handle = load_lib(path)
  result.handle = handle

  var set_globals = handle.sym_addr("set_globals")
  if set_globals == nil:
    not_allowed("load_dynlib: set_globals is not defined in the extension " & path)
  call_set_globals(set_globals)

  var init = handle.sym_addr("init")
  var init_result: Value
  if init != nil:
    init_result = cast[Init](init)(result)
  if init_result == nil:
    return
  case init_result.kind:
  of VkException:
    raise init_result.exception
  of VkNamespace:
    result.ns = init_result.ns
  else:
    todo("load_dynlib " & $init_result.kind)

proc call_set_globals(p: pointer) =
  cast[SetGlobals](p)(
    get_global_dispatcher(),
    Translators,
    GeneTranslators,
    VM,
    eval_catch,
    eval_wrap,
    translate_catch,
    translate_wrap,
    call_catch,
    call_wrap,
    fn_wrap,
    method_wrap,
  )

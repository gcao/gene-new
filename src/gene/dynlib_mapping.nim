import dynlib, tables
import asyncdispatch

import ./map_key
import ./types
import ./translators
import ./interpreter_base

# Design:
# * Exception handling
#   Pass a wrapper proc to the dynamic lib to eval and catch any exception thrown.
#   Similar logic has to be applied when extension is called from main app.
#
# Resources:
# https://gradha.github.io/articles/2015/01/writing-c-libraries-with-nim.html

type
  Init = proc(): Value {.nimcall.}

  SetGlobals = proc(
    g_disp          : PDispatcher,
    mapping         : Mapping,
    translators     : TableRef[ValueKind, Translator],
    gene_translators: TableRef[string, Translator],
    vm              : VirtualMachine,
    global_ns       : Value,
    gene_ns         : Value,
    gene_native_ns  : Value,
    genex_ns        : Value,
    object_class    : Value,
    class_class     : Value,
    exception_class : Value,
    future_class    : Value,
    namespace_class : Value,
    mixin_class     : Value,
    function_class  : Value,
    macro_class     : Value,
    block_class     : Value,
    nil_class       : Value,
    bool_class      : Value,
    int_class       : Value,
    float_class     : Value,
    char_class      : Value,
    string_class    : Value,
    symbol_class    : Value,
    array_class     : Value,
    map_class       : Value,
    stream_class    : Value,
    set_class       : Value,
    gene_class      : Value,
    document_class  : Value,
    file_class      : Value,
    date_class      : Value,
    datetime_class  : Value,
    time_class      : Value,
    selector_class  : Value,
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

proc load_dynlib*(path: string): Module =
  result = new_module(path)
  var handle = load_lib(path & ".dylib")
  result.handle = handle

  var set_globals = handle.sym_addr("set_globals")
  if set_globals == nil:
    not_allowed("load_dynlib: set_globals is not defined in the extension " & path)
  call_set_globals(set_globals)

  var init = handle.sym_addr("init")
  var init_result: Value
  if init != nil:
    init_result = cast[Init](init)()
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
    mapping,
    Translators,
    GeneTranslators,
    VM,
    GLOBAL_NS,
    GENE_NS,
    GENE_NATIVE_NS,
    GENEX_NS,
    ObjectClass,
    ClassClass,
    ExceptionClass,
    FutureClass,
    NamespaceClass,
    MixinClass,
    FunctionClass,
    MacroClass,
    BlockClass,
    NilClass,
    BoolClass,
    IntClass,
    FloatClass,
    CharClass,
    StringClass,
    SymbolClass,
    ArrayClass,
    MapClass,
    StreamClass,
    SetClass,
    GeneClass,
    DocumentClass,
    FileClass,
    DateClass,
    DatetimeClass,
    TimeClass,
    SelectorClass,
    eval_catch,
    eval_wrap,
    translate_catch,
    translate_wrap,
    call_catch,
    call_wrap,
    fn_wrap,
    method_wrap,
  )

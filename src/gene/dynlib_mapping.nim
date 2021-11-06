import dynlib, tables

import ./map_key
import ./types

type
  Init = proc() {.nimcall.}

  SetGlobals = proc(
    keys           : seq[string],
    key_mapping    : Table[string, MapKey],
    vm             : VirtualMachine,
    global_ns      : Value,
    gene_ns        : Value,
    gene_native_ns : Value,
    genex_ns       : Value,
    object_class   : Value,
    class_class    : Value,
    exception_class: Value,
    future_class   : Value,
    namespace_class: Value,
    mixin_class    : Value,
    function_class : Value,
    macro_class    : Value,
    block_class    : Value,
    nil_class      : Value,
    bool_class     : Value,
    int_class      : Value,
    float_class    : Value,
    char_class     : Value,
    string_class   : Value,
    symbol_class   : Value,
    array_class    : Value,
    map_class      : Value,
    stream_class   : Value,
    set_class      : Value,
    gene_class     : Value,
    document_class : Value,
    file_class     : Value,
    date_class     : Value,
    datetime_class : Value,
    time_class     : Value,
    selector_class : Value,
  ) {.nimcall.}

proc call_set_globals(p: pointer)

var DynlibMapping = Table[string, LibHandle]()

proc load_dynlib*(path: string): LibHandle =
  if DynlibMapping.has_key(path):
    return DynlibMapping[path]

  result = load_lib(path & ".dylib")
  var set_globals = result.sym_addr("set_globals")
  if set_globals == nil:
    not_allowed("load_dynlib: set_globals is not defined in the extension " & path)
  call_set_globals(set_globals)
  var init = result.sym_addr("init")
  if init == nil:
    not_allowed("load_dynlib: init is not defined in the extension " & path)
  cast[Init](init)()
  DynlibMapping[path] = result

# TODO:
# proc unload_dynlib*(path: string) =
#   discard

proc call_set_globals(p: pointer) =
  cast[SetGlobals](p)(
    Keys,
    KeyMapping,
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
    SelectorClass
  )

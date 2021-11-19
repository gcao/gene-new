import tables

import gene/map_key
import gene/types
import gene/translators

# All extensions should include `ext_common` like below
# include gene/ext_common
# `set_globals` will be called when the extension is loaded.

var eval_catch*: EvalCatch
var eval_wrap*: EvalWrap
var translate_catch*: TranslateCatch
var translate_wrap*: TranslateWrap
var fn_wrap: NativeFnWrap
var method_wrap: NativeMethodWrap

proc eval*(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  result = self.eval_catch(frame, expr)
  if result != nil and result.kind == VkException:
    raise result.exception

proc translate*(value: Value): Expr =
  result = translate_catch(value)
  if result != nil and result of ExException:
    raise cast[ExException](result).ex

converter to_value*(v: Namespace): Value =
  Value(kind: VkNamespace, ns: v)

converter to_value*(v: NativeFn): Value =
  Value(
    kind: VkNativeFn2,
    native_fn2: fn_wrap(v),
  )

proc set_globals*(
  m               : Mapping,
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
  ecatch          : EvalCatch,
  ewrap           : EvalWrap,
  tcatch          : TranslateCatch,
  twrap           : TranslateWrap,
  fwrap           : NativeFnWrap,
  mwrap           : NativeMethodWrap,
) {.dynlib exportc.} =
  mapping         = m
  Translators     = translators
  GeneTranslators = gene_translators
  VM              = vm
  GLOBAL_NS       = global_ns
  GENE_NS         = gene_ns
  GENE_NATIVE_NS  = gene_native_ns
  GENEX_NS        = genex_ns
  ObjectClass     = object_class
  ClassClass      = class_class
  ExceptionClass  = exception_class
  FutureClass     = future_class
  NamespaceClass  = namespace_class
  MixinClass      = mixin_class
  FunctionClass   = function_class
  MacroClass      = macro_class
  BlockClass      = block_class
  NilClass        = nil_class
  BoolClass       = bool_class
  IntClass        = int_class
  FloatClass      = float_class
  CharClass       = char_class
  StringClass     = string_class
  SymbolClass     = symbol_class
  ArrayClass      = array_class
  MapClass        = map_class
  StreamClass     = stream_class
  SetClass        = set_class
  GeneClass       = gene_class
  DocumentClass   = document_class
  FileClass       = file_class
  DateClass       = date_class
  DatetimeClass   = datetime_class
  TimeClass       = time_class
  SelectorClass   = selector_class
  eval_catch      = ecatch
  eval_wrap       = ewrap
  translate_catch = tcatch
  translate_wrap  = twrap
  fn_wrap         = fwrap
  method_wrap     = mwrap

import gene/map_key
import gene/types

# All extensions should include `ext_common` like below
# include gene/ext_common
# `set_globals` will be called when the extension is loaded.

proc set_globals*(
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
) {.dynlib exportc.} =
  Keys = keys

import dynlib, tables

var DynlibMapping = Table[string, LibHandle]()

proc load_dynlib*(path: string): LibHandle =
  if DynlibMapping.has_key(path):
    result = DynlibMapping[path]
  else:
    result = load_lib(path & ".dylib")
    DynlibMapping[path] = result

# proc unload_dynlib*(path: string) =
#   discard

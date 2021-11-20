import strutils, tables, dynlib

import ../dynlib_mapping
import ../types
import ../map_key
import ../translators
import ../interpreter

let INHERIT_KEY*               = add_key("inherit")

type
  ExImport* = ref object of Expr
    matcher*: ImportMatcherRoot
    `from`*: Expr
    pkg*: Expr
    inherit*: Expr
    native*: bool

  ImportMatcherRoot* = ref object
    children*: seq[ImportMatcher]
    `from`*: Value

  ImportMatcher* = ref object
    name*: MapKey
    `as`*: MapKey
    children*: seq[ImportMatcher]
    children_only*: bool # true if self should not be imported

proc new_import_matcher(s: string): ImportMatcher =
  var parts = s.split(":")
  case parts.len:
  of 1:
    return ImportMatcher(name: parts[0].to_key)
  of 2:
    return ImportMatcher(name: parts[0].to_key, `as`: parts[1].to_key)
  else:
    todo("new_import_matcher " & s)

proc parse*(self: ImportMatcherRoot, input: Value, group: ptr seq[ImportMatcher]) =
  var data: seq[Value]
  case input.kind:
  of VkGene:
    data = input.gene_data
  of VkVector:
    data = input.vec
  else:
    todo()

  var i = 0
  while i < data.len:
    var item = data[i]
    i += 1
    case item.kind:
    of VkSymbol:
      if item.symbol == "from":
        self.from = data[i]
        i += 1
      else:
        group[].add(new_import_matcher(item.symbol))
    of VkComplexSymbol:
      var names: seq[string] = @[]
      names.add(item.csymbol[0])
      for item in item.csymbol[1..^1]:
        names.add(item)

      var matcher: ImportMatcher
      var my_group = group
      var j = 0
      while j < names.len:
        var name = names[j]
        j += 1
        if name == "": # TODO: throw error if "" is not the last
          self.parse(data[i], matcher.children.addr)
          i += 1
        else:
          matcher = new_import_matcher(name)
          matcher.children_only = j < names.len
          my_group[].add(matcher)
          my_group = matcher.children.addr
    else:
      todo()

proc new_import_matcher*(v: Value): ImportMatcherRoot =
  result = ImportMatcherRoot()
  result.parse(v, result.children.addr)

proc import_module*(self: VirtualMachine, name: MapKey, code: string): Namespace =
  if self.modules.has_key(name):
    return self.modules[name]

  var module = new_module(name.to_s)
  var frame = new_frame()
  frame.ns = module.ns
  frame.scope = new_scope()
  discard self.eval(frame, code)
  result = module.ns
  self.modules[name] = result

proc import_module*(self: VirtualMachine, name: MapKey, code: string, inherit: Namespace): Namespace =
  var module = new_module(inherit, name.to_s)
  var frame = new_frame()
  frame.ns = module.ns
  frame.scope = new_scope()
  discard self.eval(frame, code)
  result = module.ns

proc import_from_ns*(self: VirtualMachine, frame: Frame, source: Namespace, group: seq[ImportMatcher]) =
  for m in group:
    if m.name == MUL_KEY:
      for k, v in source.members:
        frame.ns.members[k] = v
    else:
      var value = source[m.name]
      if m.children_only:
        self.import_from_ns(frame, value.ns, m.children)
      else:
        var name = m.name
        if m.as != 0:
          name = m.as
        frame.ns.members[name] = value

proc prefetch_from_dynlib(self: Module, names: seq[string]) =
  for name in names:
    if not self.ns.has_key(name.to_key):
      var v = self.handle.sym_addr(name)
      if v == nil:
        not_allowed("prefetch_from_dynlib: " & name & " is not found in " & self.name)
      else:
        self.ns[name] = Value(kind: VkNativeFn, native_fn: cast[NativeFn](v))

proc eval_import(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExImport](expr)
  var ns: Namespace
  var dir = ""
  # if frame.ns.has_key(PKG_KEY):
  #   var pkg = frame.ns[PKG_KEY].internal.pkg
  #   dir = pkg.dir & "/"
  # # TODO: load import_pkg on demand
  # # Set dir to import_pkg's root directory

  var `from` = expr.from
  if expr.native:
    var `from` = self.eval(frame, `from`).str
    var path = dir & `from`
    var module: Module
    if self.modules.has_key(path.to_key):
      ns = self.modules[path.to_key]
      module = ns.module
    else:
      module = load_dynlib(path)
      ns = module.ns
      self.modules[path.to_key] = ns
    var names: seq[string] = @[]
    for m in expr.matcher.children:
      names.add(m.name.to_s)
    module.prefetch_from_dynlib(names)
  elif `from` == nil:
    # If "from" is not given, import from parent of root namespace.
    ns = frame.ns.root.parent
  else:
    var `from` = self.eval(frame, `from`).str
    var path = dir & `from`
    if expr.inherit != nil:
      var inherit = self.eval(frame, expr.inherit).ns
      var code = read_file(path & ".gene")
      ns = self.import_module(path.to_key, code, inherit)
    elif self.modules.has_key(path.to_key):
      ns = self.modules[path.to_key]
    else:
      var code = read_file(path & ".gene")
      ns = self.import_module(path.to_key, code)
      self.modules[path.to_key] = ns
  self.import_from_ns(frame, ns, expr.matcher.children)

proc translate_import(value: Value): Expr =
  var matcher = new_import_matcher(value)
  var e = ExImport(
    evaluator: eval_import,
    matcher: matcher,
    native: value.gene_type.symbol == "import_native",
  )
  if matcher.from != nil:
    e.from = translate(matcher.from)
  if value.gene_props.has_key(PKG_KEY):
    e.pkg = translate(value.gene_props[PKG_KEY])
  if value.gene_props.has_key(INHERIT_KEY):
    e.inherit = translate(value.gene_props[INHERIT_KEY])
  return e

proc init*() =
  GeneTranslators["import"] = translate_import
  GeneTranslators["import_native"] = translate_import

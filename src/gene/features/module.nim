import strutils, tables, sugar

import ../types
import ../map_key
import ../translators
import ../interpreter

let SOURCE_KEY*  = add_key("source")
let INHERIT_KEY* = add_key("inherit")

type
  ExImport* = ref object of Expr
    matcher*: ImportMatcherRoot
    `from`*: Expr
    pkg*: Expr
    inherit*: Expr
    source*: Expr   # if source is not provided, use heuristic method to find where the source is
    # native*: bool

  ExReload* = ref object of Expr
    module*: Expr
    source*: Expr

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

proc import_module*(self: VirtualMachine, name: MapKey, code: string): Module =
  if self.modules.has_key(name):
    return self.modules[name]

  result = new_module(name.to_s)
  var frame = new_frame()
  frame.ns = result.ns
  frame.scope = new_scope()
  discard self.eval(frame, code)
  self.modules[name] = result

proc import_module*(self: VirtualMachine, name: MapKey, code: string, inherit: Namespace): Module =
  var module = new_module(inherit, name.to_s)
  var frame = new_frame()
  frame.ns = module.ns
  frame.scope = new_scope()
  discard self.eval(frame, code)
  result = module

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

proc import_from_ns*(self: VirtualMachine, frame: Frame, source: Namespace, group: seq[ImportMatcher], path: seq[MapKey]) =
  for m in group:
    if m.name == MUL_KEY:
      for k, _ in source.members:
        var p = path.dup
        p.add(k)
        frame.ns.members[k] = new_gene_reloadable(source.module, p)
    else:
      var value = source[m.name]
      var p = path.dup
      p.add(m.name)
      if m.children_only:
        self.import_from_ns(frame, value.ns, m.children, p)
      else:
        var name = m.name
        if m.as != 0:
          name = m.as
        frame.ns.members[name] = new_gene_reloadable(source.module, p)

proc sync(self: Namespace, ns: Namespace) =
  for k, v in self.members:
    if ns.members.has_key(k):
      var new_val = ns.members[k]
      self.members[k] = new_val
    else:
      ns.members.del(k)

proc reload_module*(self: VirtualMachine, name: MapKey, code: string, ns: Namespace) =
  var module = new_module(name.to_s)
  var frame = new_frame()
  frame.ns = module.ns
  frame.scope = new_scope()
  discard self.eval(frame, code)
  ns.sync(module.ns)

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
  # if expr.native:
  #   var path = self.eval(frame, `from`).str
  #   let lib = load_dynlib(dir & path)
  #   if lib == nil:
  #     todo()
  #   else:
  #     for m in expr.import_matcher.children:
  #       var v = lib.sym_addr(m.name.to_s)
  #       if v == nil:
  #         todo()
  #       else:
  #         self.def_member(frame, m.name, new_gene_internal(cast[NativeFn](v)), true)
  # else:
  # If "from" is not given, import from parent of root namespace.
  if `from` == nil:
    ns = frame.ns.root.parent
  else:
    var `from` = self.eval(frame, `from`).str
    if expr.inherit != nil:
      var inherit = self.eval(frame, expr.inherit).ns
      var code = read_file(dir & `from` & ".gene")
      ns = self.import_module(`from`.to_key, code, inherit).ns
    else:
      var code = ""
      if expr.source != nil:
        code = self.eval(frame, expr.source).str
      else:
        code = read_file(dir & `from` & ".gene")
      var module = self.import_module(`from`.to_key, code)
      ns = module.ns
      self.modules[`from`.to_key] = module

  if ns.module != nil and ns.module.reloadable:
    var path: seq[MapKey] = @[]
    self.import_from_ns(frame, ns, expr.matcher.children, path)
  else:
    self.import_from_ns(frame, ns, expr.matcher.children)

proc translate_import(value: Value): Expr =
  var matcher = new_import_matcher(value)
  var e = ExImport(
    evaluator: eval_import,
    matcher: matcher,
  )
  if matcher.from != nil:
    e.from = translate(matcher.from)
  if value.gene_props.has_key(PKG_KEY):
    e.pkg = translate(value.gene_props[PKG_KEY])
  # if value.gene_props.has_key(NATIVE_KEY):
  #   e.native = value.gene_props[NATIVE_KEY]).bool
  if value.gene_props.has_key(INHERIT_KEY):
    e.inherit = translate(value.gene_props[INHERIT_KEY])
  if value.gene_props.has_key(SOURCE_KEY):
    e.source = translate(value.gene_props[SOURCE_KEY])
  return e

proc reload_module*(self: VirtualMachine, frame: Frame, name: string, code: string) =
  var loaded_module = self.modules[name.to_key]
  if loaded_module.is_nil:
    not_allowed("reload_module: " & loaded_module.name & " must be imported before being reloaded.")
  elif not loaded_module.reloadable:
    not_allowed("reload_module: " & loaded_module.name & " is not reloadable.")

  var module = new_module(name)
  var new_frame = new_frame()
  new_frame.ns = module.ns
  new_frame.scope = new_scope()
  discard self.eval(new_frame, code)

  # Replace root ns attached to the original module object
  loaded_module.ns = module.ns

proc eval_reload(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExReload](expr)
  var name = self.eval(frame, expr.module).str
  var code = self.eval(frame, expr.source).str
  self.reload_module(frame, name, code)

proc translate_reload(value: Value): Expr =
  ExReload(
    evaluator: eval_reload,
    module: translate(value.gene_data[0]),
    source: translate(value.gene_data[1]),
  )

proc init*() =
  GeneTranslators["import"] = translate_import
  GeneTranslators["$reload"] = translate_reload

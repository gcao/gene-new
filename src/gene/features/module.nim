import strutils, tables
import std/os, pathnorm
import dynlib

import ../dynlib_mapping
import ../types
import ../interpreter_base

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
    name*: string
    `as`*: string
    children*: seq[ImportMatcher]
    children_only*: bool # true if self should not be imported

proc new_import_matcher(s: string): ImportMatcher =
  var parts = s.split(":")
  case parts.len:
  of 1:
    return ImportMatcher(name: parts[0])
  of 2:
    return ImportMatcher(name: parts[0], `as`: parts[1])
  else:
    todo("new_import_matcher " & s)

proc parse*(self: ImportMatcherRoot, input: Value, group: ptr seq[ImportMatcher]) =
  var children: seq[Value]
  case input.kind:
  of VkGene:
    children = input.gene_children
  of VkVector:
    children = input.vec
  else:
    todo()

  var i = 0
  while i < children.len:
    var item = children[i]
    i += 1
    case item.kind:
    of VkSymbol:
      if item.str == "from":
        self.from = children[i]
        i += 1
      else:
        group[].add(new_import_matcher(item.str))
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
          self.parse(children[i], matcher.children.addr)
          i += 1
        else:
          matcher = new_import_matcher(name)
          matcher.children_only = j < names.len
          my_group[].add(matcher)
          my_group = matcher.children.addr
    else:
      todo("parse " & $item.kind)

proc new_import_matcher*(v: Value): ImportMatcherRoot =
  result = ImportMatcherRoot()
  result.parse(v, result.children.addr)

proc import_module*(self: VirtualMachine, pkg: Package, name: string, code: string): Namespace =
  if self.modules.has_key(name):
    return self.modules[name]

  var module = new_module(pkg, name.to_s)
  var frame = new_frame(FrModule)
  frame.ns = module.ns
  frame.scope = new_scope()
  discard self.eval(frame, code)
  result = module.ns
  self.modules[name] = result

proc import_module*(self: VirtualMachine, pkg: Package, name: string, code: string, inherit: Namespace): Namespace =
  var module = new_module(pkg, name.to_s, inherit)
  var frame = new_frame(FrModule)
  frame.ns = module.ns
  frame.scope = new_scope()
  discard self.eval(frame, code)
  result = module.ns

proc import_from_ns*(self: VirtualMachine, frame: Frame, source: Namespace, group: seq[ImportMatcher]) =
  for m in group:
    if m.name == "*":
      for k, v in source.members:
        frame.ns.members[k] = v
    else:
      var value: Value
      if source.has_key(m.name):
        value = source[m.name]
      elif source.on_member_missing.len > 0:
        var ns = Value(kind: VkNamespace, ns: source)
        var args = new_gene_gene()
        args.gene_children.add(m.name.to_s)
        for v in source.on_member_missing:
          var r = self.call(frame, ns, v, args)
          if r != nil:
            value = r
            break

      if value == nil:
        raise new_exception(NotDefinedException, m.name.to_s & " is not defined")

      if m.children_only:
        self.import_from_ns(frame, value.ns, m.children)
      else:
        var name = m.name
        if m.as != "":
          name = m.as
        frame.ns.members[name] = value

proc prefetch_from_dynlib(self: Module, names: seq[string]) =
  for name in names:
    if not self.ns.has_key(name):
      var v = self.handle.sym_addr(name)
      if v == nil:
        not_allowed("prefetch_from_dynlib: " & name & " is not found in " & self.name)
      else:
        self.ns[name] = Value(kind: VkNativeFn, native_fn: cast[NativeFn](v))

# Support
# * Absolute path
# * Relative path that starts with "." or "..", e.g. "./dir/name"
# * Relative path that does not start with "." or "..", e.g. "dir/name"
# * (Maybe) URL
#
# * Gene module
# * Native module on different OSes.
#
# Package load paths
#   Paths added programmatically - order depends on the time when they were added
#   build-dirs
#   test-dirs if running in testing mode
#   source-dirs
#   package root if not already included
#
# Q: Can load paths be removed?
proc resolve_module*(self: VirtualMachine, frame: Frame, pkg: Package, s: string, native: bool): string =
  if s.starts_with "/":
    todo("resolve_module " & s)
  elif s.starts_with ".":
    todo("resolve_module " & s)
  else:
    var s = s
    if native:
      var (dir, name, _) = split_file(s)
      when defined(Windows):
        name &= ".dll"
      elif defined(Linux):
        name = "lib" & name & ".so"
      elif defined(MacOsX):
        name = "lib" & name & ".dylib"
      if dir == "":
        s = name
      else:
        s = dir & "/" & name
    elif not s.ends_with(".gene"):
      s = s & ".gene"
    for dir in pkg.load_paths:
      var path = normalize_path(dir & "/" & s)
      if file_exists(path):
        return path
    not_allowed("resolve_module failed: " & s)

proc eval_import(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExImport](expr)
  var ns: Namespace
  var `from` = expr.from
  if `from` == nil:
    # If "from" is not given, import from parent of root namespace.
    ns = frame.ns.root.parent
  else:
    var `from` = self.eval(frame, `from`).str
    var pkg = frame.ns.package
    if expr.pkg != nil:
      var dep_name = self.eval(frame, expr.pkg).str
      pkg = pkg.dependencies[dep_name].package
    var path = self.resolve_module(frame, pkg, `from`, expr.native)
    if expr.native:
      var module: Module
      if self.modules.has_key(path):
        ns = self.modules[path]
        module = ns.module
      else:
        module = load_dynlib(pkg, path)
        ns = module.ns
        self.modules[path] = ns
      var names: seq[string] = @[]
      for m in expr.matcher.children:
        names.add(m.name.to_s)
      module.prefetch_from_dynlib(names)
    else:
      if expr.inherit != nil:
        var inherit = self.eval(frame, expr.inherit).ns
        var code = read_file(path)
        ns = self.import_module(pkg, path, code, inherit)
      elif self.modules.has_key(path):
        ns = self.modules[path]
      else:
        var code = read_file(path)
        ns = self.import_module(pkg, path, code)
        self.modules[path] = ns
  self.import_from_ns(frame, ns, expr.matcher.children)

proc translate_import*(value: Value): Expr =
  var matcher = new_import_matcher(value)
  var e = ExImport(
    evaluator: eval_import,
    matcher: matcher,
  )
  if matcher.from != nil:
    e.from = translate(matcher.from)
  if value.gene_props.has_key("pkg"):
    e.pkg = translate(value.gene_props["pkg"])
  if value.gene_props.has_key("native"):
    e.native = value.gene_props["native"].bool
  if value.gene_props.has_key("inherit"):
    e.inherit = translate(value.gene_props["inherit"])
  return e

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    VM.gene_translators["import"] = translate_import
    # $break_from_module is for early exit from a module
    # VM.gene_translators["$break_from_module"] = translate_break_from_module
    # Q: Should we have generic support for early exit from module, class body etc?
    # A: probably not

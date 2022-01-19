import strutils, tables, os, sets, pathnorm
import asyncdispatch

import ./map_key
import ./types
import ./parser
import ./repl
import ./exprs
import ./translators

type
  Invoke* = proc(self: VirtualMachine, frame: Frame, target: Value, args: Value): Value
  InvokeWrap* = proc(invoke: Invoke): Invoke

proc new_package*(dir: string): Package
proc init_package*(self: VirtualMachine, dir: string)
proc call*(self: VirtualMachine, frame: Frame, target: Value, args: Value): Value
proc call_fn_skip_args*(self: VirtualMachine, frame: Frame, target: Value): Value

#################### Application #################

proc new_app*(): Application =
  result = Application()
  var global = new_namespace("global")
  result.ns = global

#################### Package #####################

proc init_package*(self: Dependency) =
  if self.package == nil:
    var dir: string
    if self.type == "path":
      dir = self.path
    else:
      todo("init_package " & self.name)
    self.package = new_package(dir)
    self.package.reset_load_paths()

proc build_dep_tree*(self: Dependency, node: DependencyNode) =
  self.init_package()
  for _, dep in self.package.dependencies:
    var child = DependencyNode(root: node.root)
    node.children[dep.name] = child
    dep.build_dep_tree(child)

proc build_dep_tree*(self: Package): DependencyRoot =
  result = DependencyRoot()
  result.package = self
  for _, dep in self.dependencies:
    var node = DependencyNode(root: result)
    result.children[dep.name] = node
    dep.build_dep_tree(node)

proc parse_deps(deps: seq[Value]): Table[string, Dependency] =
  for dep in deps:
    var name = dep.gene_data[0].str
    var version = dep.gene_data[1].str
    var path = dep.gene_props["path".to_key].str

    var dep = Dependency(
      name: name,
      version: version,
      `type`: "path",
      path: path,
    )
    var node = DependencyNode(root: VM.app.dep_root)
    dep.build_dep_tree(node)
    result[name] = dep

proc new_package*(dir: string): Package =
  result = Package()
  var dir = normalize_path(dir)
  var d = absolute_path(dir)
  while d.len > 1:  # not "/"
    var package_file = d & "/package.gene"
    if file_exists(package_file):
      var doc = read_document(read_file(package_file))
      result.name = doc.props[NAME_KEY].str
      result.version = doc.props[VERSION_KEY]
      result.ns = new_namespace(VM.app.ns, "package:" & result.name)
      result.dir = d
      if doc.props.has_key(DEPENDENCIES_KEY):
        result.dependencies = parse_deps(doc.props[DEPENDENCIES_KEY].vec)
      return result
    else:
      d = parent_dir(d)

  result.adhoc = true
  result.name = "<adhoc>"
  result.ns = new_namespace(VM.app.ns, "package:" & result.name)
  result.dir = dir

#################### VM ##########################

proc new_vm*(app: Application): VirtualMachine =
  result = VirtualMachine(
    app: app,
  )

proc init_app_and_vm*() =
  var app = new_app()
  VM = new_vm(app)

  let gene_home = get_env("GENE_HOME", parent_dir(get_app_dir()))
  let gene_pkg = new_package(gene_home)
  gene_pkg.reset_load_paths()
  VM.runtime = Runtime(
    name: "default",
    pkg: gene_pkg,
  )

  VM.init_package(get_current_dir())

  GLOBAL_NS = Value(kind: VkNamespace, ns: VM.app.ns)
  GLOBAL_NS.ns[STDIN_KEY]  = stdin
  GLOBAL_NS.ns[STDOUT_KEY] = stdout
  GLOBAL_NS.ns[STDERR_KEY] = stderr

  GENE_NS = Value(kind: VkNamespace, ns: new_namespace("gene"))
  GENE_NATIVE_NS = Value(kind: VkNamespace, ns: new_namespace("native"))
  GENE_NS.ns[GENE_NATIVE_NS.ns.name] = GENE_NATIVE_NS
  GLOBAL_NS.ns[GENE_NS.ns.name] = GENE_NS

  GENEX_NS = Value(kind: VkNamespace, ns: new_namespace("genex"))
  GLOBAL_NS.ns[GENEX_NS.ns.name] = GENEX_NS

  for callback in VmCreatedCallbacks:
    callback(VM)

proc wait_for_futures*(self: VirtualMachine) =
  try:
    run_forever()
  except ValueError as e:
    if e.msg == "No handles or timers registered in dispatcher.":
      discard
    else:
      raise

proc prepare*(self: VirtualMachine, code: string): Value =
  var parsed = read_all(code)
  case parsed.len:
  of 0:
    Nil
  of 1:
    parsed[0]
  else:
    new_gene_stream(parsed)

proc init_package*(self: VirtualMachine, dir: string) =
  self.app.pkg = new_package(dir)
  self.app.pkg.reset_load_paths()
  self.app.dep_root = self.app.pkg.build_dep_tree()

proc eval_prepare*(self: VirtualMachine, pkg: Package): Frame =
  var module = new_module(pkg)
  result = new_frame()
  result.ns = module.ns
  result.scope = new_scope()

proc eval*(self: VirtualMachine, frame: Frame, code: string): Value =
  var expr = translate(self.prepare(code))
  result = self.eval(frame, expr)

proc eval*(self: VirtualMachine, pkg: Package, code: string): Value =
  var module = new_module(pkg)
  var frame = new_frame()
  frame.ns = module.ns
  frame.scope = new_scope()
  self.eval(frame, code)

proc eval*(self: VirtualMachine, code: string): Value =
  self.eval(VM.app.pkg, code)

proc run_file*(self: VirtualMachine, file: string): Value =
  var module = new_module(VM.app.pkg, file, self.app.pkg.ns)
  VM.main_module = module
  var frame = new_frame()
  frame.ns = module.ns
  frame.scope = new_scope()
  var code = read_file(file)
  result = self.eval(frame, code)
  self.wait_for_futures()

proc repl_on_error*(self: VirtualMachine, frame: Frame, e: ref system.Exception): Value =
  echo "An exception was thrown: " & e.msg
  echo "Opening debug console..."
  echo "Note: the exception can be accessed as $ex"
  var ex = error_to_gene(e)
  frame.scope.def_member(CUR_EXCEPTION_KEY, ex)
  result = repl(self, frame, eval, true)

#################### Parsing #####################

proc parse*(self: var RootMatcher, v: Value)

proc calc_next*(self: var Matcher) =
  var last: Matcher = nil
  for m in self.children.mitems:
    m.calc_next()
    if m.kind in @[MatchData, MatchLiteral]:
      if last != nil:
        last.next = m
      last = m

proc calc_next*(self: var RootMatcher) =
  var last: Matcher = nil
  for m in self.children.mitems:
    m.calc_next()
    if m.kind in @[MatchData, MatchLiteral]:
      if last != nil:
        last.next = m
      last = m

proc calc_min_left*(self: var Matcher) =
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    var m = self.children[i]
    m.calc_min_left()
    m.min_left = min_left
    if m.required:
      min_left += 1

proc calc_min_left*(self: var RootMatcher) =
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    var m = self.children[i]
    m.calc_min_left()
    m.min_left = min_left
    if m.required:
      min_left += 1

proc parse(self: var RootMatcher, group: var seq[Matcher], v: Value) =
  case v.kind:
  of VkSymbol:
    if v.symbol[0] == '^':
      var m = new_matcher(self, MatchProp)
      if v.symbol.ends_with("..."):
        m.is_splat = true
        if v.symbol[1] == '@':
          m.name = v.symbol[2..^4].to_key
          m.is_prop = true
        else:
          m.name = v.symbol[1..^4].to_key
      else:
        if v.symbol[1] == '@':
          m.name = v.symbol[2..^1].to_key
          m.is_prop = true
        else:
          m.name = v.symbol[1..^1].to_key
      group.add(m)
    else:
      var m = new_matcher(self, MatchData)
      group.add(m)
      if v.symbol != "_":
        if v.symbol.endsWith("..."):
          m.is_splat = true
          if v.symbol[0] == '@':
            m.name = v.symbol[1..^4].to_key
            m.is_prop = true
          else:
            m.name = v.symbol[0..^4].to_key
        else:
          if v.symbol[0] == '@':
            m.name = v.symbol[1..^1].to_key
            m.is_prop = true
          else:
            m.name = v.symbol.to_key
  of VkVector:
    var i = 0
    while i < v.vec.len:
      var item = v.vec[i]
      i += 1
      if item.kind == VkVector:
        var m = new_matcher(self, MatchData)
        group.add(m)
        self.parse(m.children, item)
      else:
        self.parse(group, item)
        if i < v.vec.len and v.vec[i] == Equals:
          i += 1
          var last_matcher = group[^1]
          var value = v.vec[i]
          i += 1
          last_matcher.default_value_expr = translate(value)
  of VkQuote:
    var m = new_matcher(self, MatchLiteral)
    m.literal = v.quote
    m.name = "<literal>".to_key
    group.add(m)
  else:
    todo("parse " & $v.kind)

proc parse*(self: var RootMatcher, v: Value) =
  if v == nil or v == new_gene_symbol("_"):
    return
  self.parse(self.children, v)
  self.calc_min_left()
  self.calc_next()

proc new_arg_matcher*(value: Value): RootMatcher =
  result = new_arg_matcher()
  result.parse(value)

#################### Matching ####################

proc `[]`*(self: Value, i: int): Value =
  case self.kind:
  of VkGene:
    return self.gene_data[i]
  of VkVector:
    return self.vec[i]
  else:
    not_allowed()

proc `len`(self: Value): int =
  if self == nil:
    return 0
  case self.kind:
  of VkGene:
    return self.gene_data.len
  of VkVector:
    return self.vec.len
  else:
    not_allowed()

proc match_prop_splat*(vm: VirtualMachine, frame: Frame, self: seq[Matcher], input: Value, r: MatchResult) =
  if input == nil or self.prop_splat == EMPTY_STRING_KEY:
    return

  var map: OrderedTable[MapKey, Value]
  case input.kind:
  of VkMap:
    map = input.map
  of VkGene:
    map = input.gene_props
  else:
    return

  var splat = OrderedTable[MapKey, Value]()
  for k, v in map:
    if k notin self.props:
      splat[k] = v
  var splat_value = new_gene_map(splat)
  frame.scope.def_member(self.prop_splat, splat_value)
  # TODO: handle @a... or ^@a...

proc match(vm: VirtualMachine, frame: Frame, self: Matcher, input: Value, state: MatchState, r: MatchResult) =
  var value: Value
  case self.kind:
  of MatchData:
    if self.is_splat:
      value = new_gene_vec()
      for i in state.data_index..<input.len - self.min_left:
        # Stop if next matcher is a literal and matches input[i]
        if self.next != nil and self.next.kind == MatchLiteral and self.next.literal == input[i]:
          break
        value.vec.add(input[i])
        state.data_index += 1
    elif self.min_left < input.len - state.data_index:
      value = input[state.data_index]
      state.data_index += 1
    else:
      if self.default_value_expr != nil:
        value = vm.eval(frame, self.default_value_expr)
      else:
        r.kind = MatchMissingFields
        r.missing.add(self.name)
        return
    if self.name != EMPTY_STRING_KEY:
      frame.scope.def_member(self.name, value)
      if self.is_prop:
        frame.self.instance_props[self.name] = value
    var child_state = MatchState()
    for child in self.children:
      vm.match(frame, child, value, child_state, r)
    vm.match_prop_splat(frame, self.children, value, r)

  of MatchProp:
    if self.is_splat:
      return
    elif input.gene_props.has_key(self.name):
      value = input.gene_props[self.name]
    else:
      if self.default_value_expr != nil:
        value = vm.eval(frame, self.default_value_expr)
      else:
        r.kind = MatchMissingFields
        r.missing.add(self.name)
        return
    frame.scope.def_member(self.name, value)
    if self.is_prop:
      frame.self.instance_props[self.name] = value

  of MatchLiteral:
    value = input[state.data_index]
    state.data_index += 1
    if self.literal != value:
      todo("match " & $self.kind & ": " & $self.literal & " != " & $value)

  else:
    todo("match " & $self.kind)

proc match*(vm: VirtualMachine, frame: Frame, self: RootMatcher, input: Value): MatchResult =
  result = MatchResult()
  var children = self.children
  var state = MatchState()
  for child in children:
    vm.match(frame, child, input, state, result)
  vm.match_prop_splat(frame, children, input, result)

proc process_args*(self: VirtualMachine, frame: Frame, matcher: RootMatcher, args: Value) =
  var match_result = self.match(frame, matcher, args)
  case match_result.kind:
  of MatchSuccess:
    discard
    # for field in match_result.fields:
    #   if field.value_expr != nil:
    #     frame.scope.def_member(field.name, self.eval(frame, field.value_expr))
    #     frame.scope.def_member(field.name, field.value)
  of MatchMissingFields:
    for field in match_result.missing:
      not_allowed("Argument " & field.to_s & " is missing.")
  else:
    todo()

proc handle_args*(self: VirtualMachine, frame, new_frame: Frame, matcher: RootMatcher, args_expr: ExArguments) {.inline.} =
  case matcher.hint.mode:
  of MhNone:
    for _, v in args_expr.props.mpairs:
      discard self.eval(frame, v)
    for i, v in args_expr.data.mpairs:
      discard self.eval(frame, v)
  of MhSimpleData:
    for _, v in args_expr.props.mpairs:
      discard self.eval(frame, v)
    for i, v in args_expr.data.mpairs:
      let field = matcher.children[i]
      let value = self.eval(frame, v)
      if field.is_prop:
        new_frame.self.instance_props[field.name] = value
      else:
        new_frame.scope.def_member(field.name, value)
  else:
    var args = new_gene_gene()
    for k, v in args_expr.props.mpairs:
      args.gene_props[k] = self.eval(frame, v)
    for _, v in args_expr.data.mpairs:
      args.gene_data.add self.eval(frame, v)
    self.process_args(new_frame, matcher, args)

proc call*(self: VirtualMachine, frame: Frame, target: Value, args: Value): Value =
  case target.kind:
  of VkFunction:
    var fn_scope = new_scope()
    fn_scope.set_parent(target.fn.parent_scope, target.fn.parent_scope_max)
    var new_frame = Frame(ns: target.fn.ns, scope: fn_scope)
    new_frame.parent = frame

    self.process_args(new_frame, target.fn.matcher, args)
    result = self.call_fn_skip_args(new_frame, target)
  of VkBlock:
    var scope = new_scope()
    scope.set_parent(target.block.parent_scope, target.block.parent_scope_max)
    var new_frame = Frame(ns: target.block.ns, scope: scope)
    new_frame.parent = frame

    case target.block.matching_hint.mode:
    of MhSimpleData:
      for _, v in args.gene_props.mpairs:
        todo()
      for i, v in args.gene_data.mpairs:
        let field = target.block.matcher.children[i]
        new_frame.scope.def_member(field.name, v)
    of MhNone:
      discard
    else:
      todo()

    try:
      result = self.eval(new_frame, target.block.body_compiled)
    except Return as r:
      result = r.val
    except system.Exception as e:
      if self.repl_on_error:
        result = repl_on_error(self, frame, e)
        discard
      else:
        raise
  of VkInstance:
    var class = target.instance_class
    var meth = class.get_method(CALL_KEY)
    var fn = meth.callable.fn
    var fn_scope = new_scope()
    fn_scope.set_parent(fn.parent_scope, fn.parent_scope_max)
    var new_frame = Frame(ns: fn.ns, scope: fn_scope)
    new_frame.self = target
    new_frame.parent = frame

    self.process_args(new_frame, fn.matcher, args)
    result = self.call_fn_skip_args(new_frame, meth.callable)
  else:
    # TODO: Support
    # VkInstance => call "call" method on the instance class
    # VkAny / VkCustom => similar to VkInstance
    # VkClass => create instance and call the constructor
    # VkNativeFn/VkNativeFn2 => call the native function/procedure
    todo($target.kind)

proc call_fn_skip_args*(self: VirtualMachine, frame: Frame, target: Value): Value =
  if target.fn.body_compiled == nil:
    target.fn.body_compiled = translate(target.fn.body)

  try:
    result = self.eval(frame, target.fn.body_compiled)
  except Return as r:
    # return's frame is the same as new_frame(current function's frame)
    if r.frame == frame:
      result = r.val
    else:
      raise
  except system.Exception as e:
    if self.repl_on_error:
      result = repl_on_error(self, frame, e)
      discard
    else:
      raise
  if target.fn.async and result.kind != VkFuture:
    var future = new_future[Value]()
    future.complete(result)
    result = new_gene_future(future)

proc call_catch*(self: VirtualMachine, frame: Frame, target: Value, args: Value): Value =
  try:
    result = self.call(frame, target, args)
  except system.Exception as e:
    result = Value(
      kind: VkException,
      exception: e,
    )

proc call_wrap*(invoke: Invoke): Invoke =
  return proc(self: VirtualMachine, frame: Frame, target: Value, args: Value): Value =
    result = invoke(self, frame, target, args)
    if result != nil and result.kind == VkException:
      raise result.exception

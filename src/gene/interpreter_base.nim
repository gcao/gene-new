import strutils, tables, os, sets, pathnorm
import asyncdispatch
import macros

import ./map_key
import ./types
import ./parser
import ./repl

type
  Invoke* = proc(self: VirtualMachine, frame: Frame, target: Value, args: Value): Value
  InvokeWrap* = proc(invoke: Invoke): Invoke

proc new_package*(dir: string): Package
proc init_package*(self: VirtualMachine, dir: string)
proc parse_deps(deps: seq[Value]): Table[string, Dependency]
proc get_member*(self: Value, name: MapKey): Value
proc translate*(value: Value): Expr
proc translate*(stmts: seq[Value]): Expr
proc call*(self: VirtualMachine, frame: Frame, target: Value, args: Value): Value
proc call_fn_skip_args*(self: VirtualMachine, frame: Frame, target: Value): Value
proc invoke*(self: VirtualMachine, frame: Frame, instance: Value, method_name: MapKey, args: Value): Value
proc invoke*(self: VirtualMachine, frame: Frame, instance: Value, method_name: MapKey, args_expr: var Expr): Value

#################### Value #######################

proc to_s*(self: Value): string =
  if self.is_nil:
    return ""
  case self.kind:
    of VkNil:
      return ""
    of VkString:
      return self.str
    of VkInstance:
      var method_key = "to_s".to_key
      var m = self.instance_class.get_method(method_key)
      if m.class != ObjectClass.class:
        var frame = new_frame()
        var args = new_gene_gene()
        return VM.invoke(frame, self, method_key, args).str
    else:
      discard

  return $self

#################### Package #####################

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
    var name = dep.gene_children[0].str
    var version = dep.gene_children[1].str
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

#################### Pattern Parsing #############

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
    if v.str[0] == '^':
      var m = new_matcher(self, MatchProp)
      if v.str.ends_with("..."):
        m.is_splat = true
        if v.str[1] == '@':
          m.name = v.str[2..^4].to_key
          m.is_prop = true
        else:
          m.name = v.str[1..^4].to_key
      else:
        if v.str[1] == '@':
          m.name = v.str[2..^1].to_key
          m.is_prop = true
        else:
          m.name = v.str[1..^1].to_key
      group.add(m)
    else:
      var m = new_matcher(self, MatchData)
      group.add(m)
      if v.str != "_":
        if v.str.endsWith("..."):
          m.is_splat = true
          if v.str[0] == '@':
            m.name = v.str[1..^4].to_key
            m.is_prop = true
          else:
            m.name = v.str[0..^4].to_key
        else:
          if v.str[0] == '@':
            m.name = v.str[1..^1].to_key
            m.is_prop = true
          else:
            m.name = v.str.to_key
  of VkComplexSymbol:
    if v.csymbol[0] == '^':
      todo("parse " & $v)
    else:
      var m = new_matcher(self, MatchData)
      group.add(m)
      m.is_prop = true
      var name = v.csymbol[1]
      if name.ends_with("..."):
        m.is_splat = true
        m.name = name[0..^4].to_key
      else:
        m.name = name.to_key
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

#################### Pattern Matching ############

proc `[]`*(self: Value, i: int): Value =
  case self.kind:
  of VkGene:
    return self.gene_children[i]
  of VkVector:
    return self.vec[i]
  else:
    not_allowed()

proc `len`(self: Value): int =
  if self == nil:
    return 0
  case self.kind:
  of VkGene:
    return self.gene_children.len
  of VkVector:
    return self.vec.len
  else:
    not_allowed()

proc match_prop_splat*(vm: VirtualMachine, frame: Frame, self: seq[Matcher], input: Value, r: MatchResult) =
  if input == nil or self.prop_splat == EMPTY_STRING_KEY:
    return

  var map: Table[MapKey, Value]
  case input.kind:
  of VkMap:
    map = input.map
  of VkGene:
    map = input.gene_props
  else:
    return

  var splat = Table[MapKey, Value]()
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
    elif input.kind == VkGene and input.gene_props.has_key(self.name):
      value = input.gene_props[self.name]
    elif input.kind == VkMap and input.map.has_key(self.name):
      value = input.map[self.name]
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

#################### ExLiteral ###################

type
  ExLiteral* = ref object of Expr
    data*: Value

proc eval_literal(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  cast[ExLiteral](expr).data

proc new_ex_literal*(v: Value): ExLiteral =
  ExLiteral(
    evaluator: eval_literal,
    data: v,
  )

#################### ExString ###################

type
  ExString* = ref object of Expr
    data*: string

proc eval_string(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  return "" & cast[ExString](expr).data

proc new_ex_string*(v: Value): ExString =
  ExString(
    evaluator: eval_string,
    data: v.str,
  )

#################### ExGroup #####################

type
  ExGroup* = ref object of Expr
    children*: seq[Expr]

proc eval_group*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  for item in cast[ExGroup](expr).children.mitems:
    result = self.eval(frame, item)

proc new_ex_group*(): ExGroup =
  result = ExGroup(
    evaluator: eval_group,
  )

#################### ExException #################

type
  ExException* = ref object of Expr
    ex*: ref system.Exception

proc eval_exception(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  # raise cast[ExException](expr).ex
  not_allowed("eval_exception")

proc new_ex_exception*(ex: ref system.Exception): ExException =
  ExException(
    evaluator: eval_exception, # Should never be called
    ex: ex,
  )

macro wrap_exception*(p: untyped): untyped =
  if p.kind == nnkProcDef:
    var convert: string
    var ret_type = $p[3][0]
    case ret_type:
    of "Value":
      convert = "exception_to_value"
    of "Expr":
      convert = "new_ex_exception"
    else:
      todo("wrap_exception does NOT support returning type of " & ret_type)

    p[6] = nnkTryStmt.newTree(
      p[6],
      nnkExceptBranch.newTree(
        infix(newDotExpr(ident"system", ident"Exception"), "as", ident"ex"),
        nnkReturnStmt.newTree(
          nnkCall.newTree(ident(convert), ident"ex"),
        ),
      ),
    )
    return p
  else:
    todo("ex2val " & $nnkProcDef)

#################### ExExplode ###################

type
  ExExplode* = ref object of Expr
    data*: Expr

proc eval_explode*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var data = self.eval(frame, cast[ExExplode](expr).data)
  Value(
    kind: VkExplode,
    explode: data,
  )

proc new_ex_explode*(): ExExplode =
  result = ExExplode(
    evaluator: eval_explode,
  )

#################### ExArguments #################

type
  ExArguments* = ref object of Expr
    has_explode*: bool
    props*: Table[MapKey, Expr]
    children*: seq[Expr]

proc check_explode*(self: var ExArguments) =
  for child in self.children:
    if child of ExExplode:
      self.has_explode = true
      return

proc eval_args*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExArguments](expr)
  result = new_gene_gene()
  for k, v in expr.props.mpairs:
    result.gene_props[k] = self.eval(frame, v)
  for _, v in expr.children.mpairs:
    var value = self.eval(frame, v)
    if value.is_nil:
      discard
    elif value.kind == VkExplode:
      for item in value.explode.vec:
        result.gene_children.add(item)
    else:
      result.gene_children.add(value)

proc new_ex_arg*(): ExArguments =
  result = ExArguments(
    evaluator: eval_args,
  )

proc new_ex_arg*(value: Value): ExArguments =
  result = ExArguments(
    evaluator: eval_args,
  )
  for k, v in value.gene_props:
    result.props[k] = translate(v)
  for v in value.gene_children:
    result.children.add(translate(v))
  result.check_explode()

#################### OOP #########################

type
  ExInvoke* = ref object of Expr
    self*: Expr
    meth*: MapKey
    args*: Expr

proc eval_invoke*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExInvoke](expr)
  var instance: Value
  var e = cast[ExInvoke](expr).self
  if e == nil:
    instance = frame.self
  else:
    instance = self.eval(frame, e)
  if instance == nil:
    raise new_exception(types.Exception, "Invoking " & expr.meth.to_s & " on nil.")

  self.invoke(frame, instance, expr.meth, expr.args)

proc translate_invoke*(value: Value): Expr =
  var r = ExInvoke(
    evaluator: eval_invoke,
  )
  r.self = translate(value.gene_props.get_or_default(SELF_KEY, nil))
  r.meth = value.gene_props[METHOD_KEY].str.to_key

  var args = new_ex_arg()
  for k, v in value.gene_props:
    args.props[k] = translate(v)
  for v in value.gene_children:
    args.children.add(translate(v))
  r.args = args

  result = r

#################### Selector ####################

type
  ExSet* = ref object of Expr
    target*: Expr
    selector*: Expr
    value*: Expr

  ExInvokeSelector* = ref object of Expr
    self*: Expr
    data*: seq[Expr]

proc update(self: SelectorItem, target: Value, value: Value): bool =
  for m in self.matchers:
    case m.kind:
    of SmByIndex:
      # TODO: handle negative number
      case target.kind:
      of VkVector:
        if self.is_last:
          target.vec[m.index] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.vec[m.index], value)
      of VkGene:
        if self.is_last:
          target.gene_children[m.index] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.gene_children[m.index], value)
      else:
        var class = target.get_class()
        if class.has_method(SET_CHILD_KEY):
          var args = new_gene_gene()
          args.gene_children.add(m.index)
          args.gene_children.add(value)
          return VM.invoke(new_frame(), target, SET_CHILD_KEY, args)
        else:
          not_allowed("set_child " & $target & " " & $m.index & " " & $value)
    of SmByName:
      case target.kind:
      of VkMap:
        if self.is_last:
          target.map[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.map[m.name], value)
      of VkGene:
        if self.is_last:
          target.gene_props[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.gene_props[m.name], value)
      of VkNamespace:
        if self.is_last:
          target.ns.members[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.ns.members[m.name], value)
      of VkClass:
        if self.is_last:
          target.class.ns.members[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.class.ns.members[m.name], value)
      of VkInstance:
        if self.is_last:
          result = true
          var class = target.instance_class
          if class.has_method(SET_KEY):
            var args = new_gene_gene()
            args.gene_children.add(m.name.to_s)
            args.gene_children.add(value)
            return VM.invoke(new_frame(), target, SET_KEY, args)
          else:
            target.instance_props[m.name] = value
        else:
          for child in self.children:
            result = result or child.update(target.get_member(m.name), value)
      else:
        if self.is_last:
          result = true
          var class = target.get_class()
          if class.has_method(SET_KEY):
            var args: Expr = new_ex_arg()
            cast[ExArguments](args).children.add(new_ex_literal(m.name.to_s))
            cast[ExArguments](args).children.add(new_ex_literal(value))
            return VM.invoke(new_frame(), target, SET_KEY, args)
          else:
            not_allowed("update " & $target & " " & m.name.to_s & " " & $value)
        else:
          for child in self.children:
            result = result or child.update(target.get_member(m.name), value)
    else:
      todo("update " & $m.kind & " " & $target & " " & $value)

proc update*(self: Selector, target: Value, value: Value): bool =
  for child in self.children:
    result = result or child.update(target, value)

proc eval_set*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExSet](expr)
  var target =
    if expr.target == nil:
      frame.self
    else:
      self.eval(frame, expr.target)
  var selector = self.eval(frame, expr.selector)
  result = self.eval(frame, expr.value)
  case selector.kind:
  of VkSelector:
    var success = selector.selector.update(target, result)
    if not success:
      todo("Update by selector failed.")
  of VkInt:
    case target.kind:
    of VkGene:
      target.gene_children[selector.int] = result
    of VkVector:
      target.vec[selector.int] = result
    else:
      todo($target.kind)
  of VkString:
    case target.kind:
    of VkGene:
      target.gene_props[selector.str] = result
    of VkMap:
      target.map[selector.str] = result
    else:
      todo($target.kind)
  else:
    todo($selector.kind)

proc translate_set*(value: Value): Expr =
  var e = ExSet(
    evaluator: eval_set,
  )
  if value.gene_children.len == 2:
    e.selector = translate(value.gene_children[0])
    e.value = translate(value.gene_children[1])
  else:
    e.target = translate(value.gene_children[0])
    e.selector = translate(value.gene_children[1])
    e.value = translate(value.gene_children[2])
  return e

#################### Simple Exprs ################

let BREAK_EXPR* = Expr()
BREAK_EXPR.evaluator = proc(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e: Break
  e.new
  raise e

let CONTINUE_EXPR* = Expr()
CONTINUE_EXPR.evaluator = proc(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e: Continue
  e.new
  raise e

#################### Translator ##################

var Translators*     = new_table[ValueKind, Translator]()
var GeneTranslators* = new_table[string, Translator]()

proc default_translator(value: Value): Expr =
  case value.kind:
  of VkNil, VkBool, VkInt, VkFloat, VkRegex, VkTime:
    return new_ex_literal(value)
  of VkString:
    return new_ex_string(value)
  of VkStream:
    return translate(value.stream)
  else:
    todo($value)

proc translate*(value: Value): Expr =
  var translator = Translators.get_or_default(value.kind, default_translator)
  translator(value)

proc translate*(stmts: seq[Value]): Expr =
  case stmts.len:
  of 0:
    result = new_ex_literal(nil)
  of 1:
    result = translate(stmts[0])
  else:
    result = new_ex_group()
    for stmt in stmts:
      cast[ExGroup](result).children.add(translate(stmt))

proc translate_arguments*(value: Value): Expr =
  var r = new_ex_arg()
  for k, v in value.gene_props:
    r.props[k] = translate(v)
  for v in value.gene_children:
    r.children.add(translate(v))
  r.check_explode()
  result = r

proc translate_arguments*(value: Value, eval: Evaluator): Expr =
  result = translate_arguments(value)
  result.evaluator = eval

proc translate_catch*(value: Value): Expr =
  try:
    result = translate(value)
  except system.Exception as e:
    # echo e.msg
    # echo e.get_stack_trace()
    result = new_ex_exception(e)

proc translate_wrap*(translate: Translator): Translator =
  return proc(value: Value): Expr =
    result = translate(value)
    if result != nil and result of ExException:
      raise cast[ExException](result).ex

#################### VM ##########################

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
  result = new_frame(FrModule)
  result.ns = module.ns
  result.scope = new_scope()

proc eval*(self: VirtualMachine, frame: Frame, code: string): Value =
  var expr = translate(self.prepare(code))
  result = self.eval(frame, expr)

proc eval*(self: VirtualMachine, pkg: Package, code: string): Value =
  var module = new_module(pkg)
  var frame = new_frame(FrModule)
  frame.ns = module.ns
  frame.scope = new_scope()
  self.eval(frame, code)

proc eval*(self: VirtualMachine, code: string): Value =
  self.eval(VM.app.pkg, code)

proc run_file*(self: VirtualMachine, file: string): Value =
  var module = new_module(VM.app.pkg, file, self.app.pkg.ns)
  VM.main_module = module
  var frame = new_frame(FrModule)
  frame.ns = module.ns
  frame.scope = new_scope()
  var code = read_file(file)
  result = self.eval(frame, code)
  self.wait_for_futures()

proc repl_on_error*(self: VirtualMachine, frame: Frame, e: ref system.Exception): Value =
  echo "An exception was thrown: " & e.msg
  echo "Opening debug console..."
  echo "Note: the exception can be accessed as $ex"
  var ex = exception_to_value(e)
  frame.scope.def_member(CUR_EXCEPTION_KEY, ex)
  result = repl(self, frame, eval, true)

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

proc call*(self: VirtualMachine, frame: Frame, this: Value, target: Value, args: Value): Value =
  case target.kind:
  of VkFunction:
    var fn_scope = new_scope()
    fn_scope.set_parent(target.fn.parent_scope, target.fn.parent_scope_max)
    var new_frame = Frame(ns: target.fn.ns, scope: fn_scope)
    new_frame.self = this
    new_frame.parent = frame

    self.process_args(new_frame, target.fn.matcher, args)
    result = self.call_fn_skip_args(new_frame, target)
  of VkBlock:
    var scope = new_scope()
    scope.set_parent(target.block.parent_scope, target.block.parent_scope_max)
    var new_frame = Frame(ns: target.block.ns, scope: scope)
    new_frame.self = this
    new_frame.parent = frame

    case target.block.matching_hint.mode:
    of MhSimpleData:
      for _, v in args.gene_props.mpairs:
        todo()
      for i, v in args.gene_children.mpairs:
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
    # VkAny / VkCustom => similar to VkInstance
    # VkClass => create instance and call the constructor?
    # VkNativeFn/VkNativeFn2 => call the native function/procedure
    todo($target.kind)

proc handle_args*(self: VirtualMachine, frame, new_frame: Frame, matcher: RootMatcher, args_expr: ExArguments) {.inline.} =
  case matcher.hint.mode:
  of MhNone:
    for _, v in args_expr.props.mpairs:
      discard self.eval(frame, v)
    for i, v in args_expr.children.mpairs:
      discard self.eval(frame, v)
  of MhSimpleData:
    for _, v in args_expr.props.mpairs:
      discard self.eval(frame, v)
    if args_expr.has_explode:
      var children: seq[Value] = @[]
      for i, v in args_expr.children.mpairs:
        let value = self.eval(frame, v)
        if value.kind == VkExplode:
          for item in value.explode.vec:
            children.add(item)
        else:
          children.add(value)
      for i, value in children:
        let field = matcher.children[i]
        if field.is_prop:
          new_frame.self.instance_props[field.name] = value
        else:
          new_frame.scope.def_member(field.name, value)
    else:
      for i, v in args_expr.children.mpairs:
        let field = matcher.children[i]
        let value = self.eval(frame, v)
        if field.is_prop:
          new_frame.self.instance_props[field.name] = value
        else:
          new_frame.scope.def_member(field.name, value)
  else:
    var expr = cast[Expr](args_expr)
    var args = self.eval_args(frame, nil, expr)
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
      for i, v in args.gene_children.mpairs:
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

proc invoke*(self: VirtualMachine, frame: Frame, instance: Value, method_name: MapKey, args: Value): Value =
  var class = instance.get_class
  var meth = class.get_method(method_name)
  # var is_method_missing = false
  var callable: Value
  if meth == nil:
    not_allowed("No method available: " & class.name & "." & method_name.to_s)
    # if class.method_missing == nil:
    #   not_allowed("No method available: " & expr.meth.to_s)
    # else:
    #   is_method_missing = true
    #   callable = class.method_missing
  else:
    callable = meth.callable

  case callable.kind:
  of VkNativeMethod, VkNativeMethod2:
    if callable.kind == VkNativeMethod:
      result = meth.callable.native_method(instance, args)
    else:
      result = meth.callable.native_method2(instance, args)

  of VkFunction:
    var fn_scope = new_scope()
    # if is_method_missing:
    #   fn_scope.def_member("$method_name".to_key, expr.meth.to_s)
    var new_frame = Frame(ns: callable.fn.ns, scope: fn_scope)
    new_frame.parent = frame
    new_frame.self = instance
    new_frame.extra = FrameExtra(kind: FrMethod, `method`: meth)

    if callable.fn.body_compiled == nil:
      callable.fn.body_compiled = translate(callable.fn.body)

    try:
      self.process_args(new_frame, callable.fn.matcher, args)
      result = self.eval(new_frame, callable.fn.body_compiled)
    except Return as r:
      # return's frame is the same as new_frame(current function's frame)
      if r.frame == new_frame:
        result = r.val
      else:
        raise
    except system.Exception as e:
      if self.repl_on_error:
        result = repl_on_error(self, frame, e)
        discard
      else:
        raise
  else:
    todo()

proc invoke*(self: VirtualMachine, frame: Frame, instance: Value, method_name: MapKey, args_expr: var Expr): Value =
  var class = instance.get_class
  var meth = class.get_method(method_name)
  # var is_method_missing = false
  var callable: Value
  if meth == nil:
    not_allowed("No method available: " & class.name & "." & method_name.to_s)
    # if class.method_missing == nil:
    #   not_allowed("No method available: " & expr.meth.to_s)
    # else:
    #   is_method_missing = true
    #   callable = class.method_missing
  else:
    callable = meth.callable

  case callable.kind:
  of VkNativeMethod, VkNativeMethod2:
    var args = self.eval_args(frame, nil, args_expr)
    if callable.kind == VkNativeMethod:
      result = meth.callable.native_method(instance, args)
    else:
      result = meth.callable.native_method2(instance, args)

  of VkFunction:
    var fn_scope = new_scope()
    # if is_method_missing:
    #   fn_scope.def_member("$method_name".to_key, expr.meth.to_s)
    var new_frame = Frame(ns: callable.fn.ns, scope: fn_scope)
    new_frame.parent = frame
    new_frame.self = instance
    new_frame.extra = FrameExtra(kind: FrMethod, `method`: meth)

    if callable.fn.body_compiled == nil:
      callable.fn.body_compiled = translate(callable.fn.body)

    try:
      handle_args(self, frame, new_frame, callable.fn.matcher, cast[ExArguments](args_expr))
      result = self.eval(new_frame, callable.fn.body_compiled)
    except Return as r:
      # return's frame is the same as new_frame(current function's frame)
      if r.frame == new_frame:
        result = r.val
      else:
        raise
    except system.Exception as e:
      if self.repl_on_error:
        result = repl_on_error(self, frame, e)
        discard
      else:
        raise
  else:
    todo()

proc get_member*(self: Value, name: MapKey): Value =
  var ns: Namespace
  case self.kind:
  of VkNamespace:
    ns = self.ns
  of VkClass:
    ns = self.class.ns
  of VkMixin:
    ns = self.mixin.ns
  of VkMap:
    if self.map.has_key(name):
      return self.map[name]
    else:
      return Nil
  of VkEnum:
    return new_gene_enum_member(self.enum.members[name.to_s])
  of VkInstance:
    var class = self.instance_class
    if class.has_method(GET_KEY):
      var args = new_gene_gene()
      args.gene_children.add(name.to_s)
      return VM.invoke(new_frame(), self, GET_KEY, args)
    elif self.instance_props.has_key(name):
      return self.instance_props[name]
    else:
      return Nil
  else:
    var class = self.get_class()
    if class.has_method(GET_KEY):
      var args = new_gene_gene()
      args.gene_children.add(name.to_s)
      return VM.invoke(new_frame(), self, GET_KEY, args)
    else:
      todo("get_member " & $self.kind & " " & name.to_s)

  if ns.members.has_key(name):
    return ns.members[name]
  elif ns.on_member_missing.len > 0:
    var args = new_gene_gene()
    args.gene_children.add(name.to_s)
    for v in ns.on_member_missing:
      var r = VM.call(new_frame(), self, v, args)
      if r != nil:
        return r
  raise new_exception(NotDefinedException, name.to_s & " is not defined")

proc get_child*(self: Value, index: int, vm: VirtualMachine, frame: Frame): Value =
  var index = index
  case self.kind:
  of VkVector:
    if index < 0:
      index += self.vec.len
    if index < self.vec.len:
      return self.vec[index]
    else:
      return Nil
  of VkGene:
    if index < 0:
      index += self.gene_children.len
    if index < self.gene_children.len:
      return self.gene_children[index]
    else:
      return Nil
  else:
    var class = self.get_class()
    if class.has_method(GET_CHILD_KEY):
      var args = new_gene_gene()
      args.gene_children.add(index)
      return vm.invoke(frame, self, GET_CHILD_KEY, args)
    else:
      not_allowed("get_child " & $self & " " & $index)

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
    result = self.invoke(frame, target, args)
    if result != nil and result.kind == VkException:
      raise result.exception

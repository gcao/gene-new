import strutils, tables, strutils, os, sets
import asyncdispatch
# import macros

import ./map_key
import ./types
import ./parser
import ./repl
import ./exprs
import ./translators

let GENE_HOME*    = get_env("GENE_HOME", parent_dir(get_app_dir()))
let GENE_RUNTIME* = Runtime(
  home: GENE_HOME,
  name: "default",
  # version: read_file(GENE_HOME & "/VERSION").strip(),
)

#################### Application #################

proc new_app*(): Application =
  result = Application()
  var global = new_namespace("global")
  result.ns = global

#################### Package #####################

proc parse_deps(deps: seq[Value]): Table[string, Package] =
  for dep in deps:
    var name = dep.gene_data[0].str
    var version = dep.gene_data[1]
    var location = dep.gene_props[LOCATION_KEY]
    var pkg = Package(name: name, version: version)
    pkg.dir = location.str
    result[name] = pkg

proc new_package*(dir: string): Package =
  result = Package()
  var d = absolute_path(dir)
  while d.len > 1:  # not "/"
    var package_file = d & "/package.gene"
    if file_exists(package_file):
      var doc = read_document(read_file(package_file))
      result.name = doc.props[NAME_KEY].str
      result.version = doc.props[VERSION_KEY]
      result.ns = new_namespace(VM.app.ns, "package:" & result.name)
      result.dir = d
      result.dependencies = parse_deps(doc.props[DEPS_KEY].vec)
      # result.ns[CUR_PKG_KEY] = result
      return result
    else:
      d = parent_dir(d)

  result.adhoc = true
  result.ns = new_namespace(VM.app.ns, "package:<adhoc>")
  result.dir = d
  # result.ns[CUR_PKG_KEY] = result

#################### VM ##########################

proc new_vm*(app: Application): VirtualMachine =
  result = VirtualMachine(
    app: app,
  )

proc init_app_and_vm*() =
  var app = new_app()
  VM = new_vm(app)
  GLOBAL_NS = Value(kind: VkNamespace, ns: VM.app.ns)
  GENE_NS = Value(kind: VkNamespace, ns: new_namespace("gene"))
  GENE_NATIVE_NS = Value(kind: VkNamespace, ns: new_namespace("native"))
  GENE_NS.ns[GENE_NATIVE_NS.ns.name] = GENE_NATIVE_NS
  GLOBAL_NS.ns[GENE_NS.ns.name] = GENE_NS
  GENEX_NS = Value(kind: VkNamespace, ns: new_namespace("genex"))
  GLOBAL_NS.ns[GENEX_NS.ns.name] = GENEX_NS

  for callback in VmCreatedCallbacks:
    callback(VM)

  VmCreatedCallbacks = @[]

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

proc eval_prepare*(self: VirtualMachine): Frame =
  var module = new_module()
  result = new_frame()
  result.ns = module.ns
  result.scope = new_scope()

proc eval*(self: VirtualMachine, frame: Frame, code: string): Value =
  var expr = translate(self.prepare(code))
  result = self.eval(frame, expr)

proc eval*(self: VirtualMachine, code: string): Value =
  var module = new_module()
  var frame = new_frame()
  frame.ns = module.ns
  frame.scope = new_scope()
  self.eval(frame, code)

proc run_file*(self: VirtualMachine, file: string): Value =
  var module = new_module(self.app.pkg.ns, file)
  var frame = new_frame()
  frame.ns = module.ns
  frame.scope = new_scope()
  var code = read_file(file)
  result = self.eval(frame, code)
  # discard self.eval(frame, code)
  # if frame.ns.has_key(MAIN_KEY):
  #   var main = frame[MAIN_KEY]
  #   if main.kind == VkFunction:
  #     var args = VM.app.ns[CMD_ARGS_KEY]
  #     var options = Table[FnOption, Value]()
  #     result = self.call_fn(frame, Nil, main.internal.fn, args, options)
  #   else:
  #     raise new_exception(CatchableError, "main is not a function.")
  self.wait_for_futures()

#################### Parsing #####################

proc parse*(self: var RootMatcher, v: Value)

proc calc_min_left*(self: var Matcher) =
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    var m = self.children[i]
    m.min_left = min_left
    if m.required:
      min_left += 1

proc calc_min_left*(self: var RootMatcher) =
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    var m = self.children[i]
    m.calc_min_left
    m.min_left = min_left
    if m.required:
      min_left += 1

proc parse(self: var RootMatcher, group: var seq[Matcher], v: Value) =
  case v.kind:
  of VkSymbol:
    if v.symbol[0] == '^':
      var m = new_matcher(self, MatchProp)
      if v.symbol.ends_with("..."):
        m.name = v.symbol[1..^4].to_key
        m.splat = true
      else:
        m.name = v.symbol[1..^1].to_key
      group.add(m)
    else:
      var m = new_matcher(self, MatchData)
      group.add(m)
      if v.symbol != "_":
        if v.symbol.endsWith("..."):
          m.name = v.symbol[0..^4].to_key
          m.splat = true
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
        if i < v.vec.len and v.vec[i] == new_gene_symbol("="):
          i += 1
          var last_matcher = group[^1]
          var value = v.vec[i]
          i += 1
          last_matcher.default_value_expr = translate(value)
  else:
    todo()

proc parse*(self: var RootMatcher, v: Value) =
  if v == nil or v == new_gene_symbol("_"):
    return
  self.parse(self.children, v)
  self.calc_min_left

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
  # r.fields.add(new_matched_field(self.prop_splat, new_gene_map(splat)))
  frame.scope.def_member(self.prop_splat, new_gene_map(splat))

proc match(vm: VirtualMachine, frame: Frame, self: Matcher, input: Value, state: MatchState, r: MatchResult) =
  case self.kind:
  of MatchData:
    var value: Value
    # var value_expr: Expr
    if self.splat:
      value = new_gene_vec()
      for i in state.data_index..<input.len - self.min_left:
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
      # var matched_field = new_matched_field(self.name, value)
      # matched_field.value_expr = value_expr
      # r.fields.add(matched_field)
    var child_state = MatchState()
    for child in self.children:
      vm.match(frame, child, value, child_state, r)
    vm.match_prop_splat(frame, self.children, value, r)
  of MatchProp:
    var value: Value
    # var value_expr: Expr
    if self.splat:
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
    # var matched_field = new_matched_field(self.name, value)
    # matched_field.value_expr = value_expr
    # r.fields.add(matched_field)
  else:
    todo()

proc match*(vm: VirtualMachine, frame: Frame, self: RootMatcher, input: Value): MatchResult =
  result = MatchResult()
  var children = self.children
  var state = MatchState()
  for child in children:
    vm.match(frame, child, input, state, result)
  vm.match_prop_splat(frame, children, input, result)

# macro import_folder(s: string): untyped =
#   let s = staticExec "find " & s.toStrLit.strVal & " -name '*.nim' -maxdepth 1"
#   let files = s.splitLines
#   result = newStmtList()
#   for file in files:
#     result.add(parseStmt("import " & file[0..^5] & " as feature"))

# # Below code doesn't work for some reason
# import_folder "features"

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

template handle_args*(self: VirtualMachine, frame, new_frame: Frame, fn: Function, args_expr: ExArguments) =
  case fn.matching_hint.mode:
  of MhNone:
    for _, v in args_expr.props.mpairs:
      discard self.eval(frame, v)
    for i, v in args_expr.data.mpairs:
      # var field = target.fn.matcher.children[i]
      discard self.eval(frame, v)
  of MhSimpleData:
    for _, v in args_expr.props.mpairs:
      discard self.eval(frame, v)
    for i, v in args_expr.data.mpairs:
      let field = fn.matcher.children[i]
      new_frame.scope.def_member(field.name, self.eval(frame, v))
  else:
    var args = new_gene_gene()
    for k, v in args_expr.props.mpairs:
      args.gene_props[k] = self.eval(frame, v)
    for _, v in args_expr.data.mpairs:
      args.gene_data.add self.eval(frame, v)
    self.process_args(new_frame, fn.matcher, args)

proc repl_on_error*(self: VirtualMachine, frame: Frame, e: ref CatchableError): Value =
  echo "An exception was thrown: " & e.msg
  echo "Opening debug console..."
  echo "Note: the exception can be accessed as $ex"
  var ex = error_to_gene(e)
  frame.scope.def_member(CUR_EXCEPTION_KEY, ex)
  result = repl(self, frame, eval, true)

proc call*(self: VirtualMachine, frame: Frame, target: Value, args: Value): Value =
  case target.kind:
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
    except CatchableError as e:
      if self.repl_on_error:
        result = repl_on_error(self, frame, e)
        discard
      else:
        raise
  else:
    todo()

import "./features/core" as core_feature; core_feature.init()
import "./features/symbol" as symbol_feature; symbol_feature.init()
import "./features/array" as array_feature; array_feature.init()
import "./features/map" as map_feature; map_feature.init()
import "./features/gene" as gene_feature; gene_feature.init()
import "./features/range" as range_feature; range_feature.init()
import "./features/quote" as quote_feature; quote_feature.init()
import "./features/arithmetic" as arithmetic_feature; arithmetic_feature.init()
import "./features/var" as var_feature; var_feature.init()
import "./features/assignment" as assignment_feature; assignment_feature.init()
import "./features/enum" as enum_feature; enum_feature.init()
import "./features/exception" as exception_feature; exception_feature.init()
import "./features/if" as if_feature; if_feature.init()
import "./features/if_star" as if_star_feature; if_star_feature.init()
import "./features/fp" as fp_feature; fp_feature.init()
import "./features/macro" as macro_feature; macro_feature.init()
import "./features/block" as block_feature; block_feature.init()
import "./features/async" as async_feature; async_feature.init()
import "./features/namespace" as namespace_feature; namespace_feature.init()
import "./features/selector" as selector_feature; selector_feature.init()
import "./features/native" as native_feature; native_feature.init()
import "./features/loop" as loop_feature; loop_feature.init()
import "./features/while" as while_feature; while_feature.init()
import "./features/repeat" as repeat_feature; repeat_feature.init()
import "./features/for" as for_feature; for_feature.init()
import "./features/oop" as oop_feature; oop_feature.init()
import "./features/cast" as cast_feature; cast_feature.init()
import "./features/eval" as eval_feature; eval_feature.init()
import "./features/parse" as parse_feature; parse_feature.init()
import "./features/pattern_matching" as pattern_matching_feature; pattern_matching_feature.init()
import "./features/module" as module_feature; module_feature.init()
import "./features/template" as template_feature; template_feature.init()
import "./features/print" as print_feature; print_feature.init()
import "./features/repl" as repl_feature; repl_feature.init()

import "./libs" as libs; libs.init()

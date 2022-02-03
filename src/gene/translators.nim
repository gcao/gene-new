import tables, os, nre, options, strutils, sets
import asyncdispatch

import ./map_key
import ./types
import ./parser
import ./repl

let GENE_HOME*    = get_env("GENE_HOME", parent_dir(get_app_dir()))
let GENE_RUNTIME* = Runtime(
  home: GENE_HOME,
  name: "default",
  # version: read_file(GENE_HOME & "/VERSION").strip(),
)

#################### Definitions #################

proc translate*(value: Value): Expr
proc translate*(stmts: seq[Value]): Expr
proc call_fn*(self: VirtualMachine, frame: Frame, target: Value, args: Value): Value
proc reload_module*(self: VirtualMachine, frame: Frame, name: string, code: string)

var hot_reload_counter = 0
template check_hot_reload*(self: VirtualMachine) =
  hot_reload_counter += 1
  if hot_reload_counter == 5:
    hot_reload_counter = 0
    let tried = HotReloadListener.try_recv()
    if tried.data_available:
      echo "check_hot_reload " & tried.msg
      let match = tried.msg.match(re(get_current_dir() & "/(.*)" & "\\.gene"))
      # Not sure why I have to use options.is_some/get and nre.captures here. Maybe there is some name collisions?
      if options.is_some(match):
        let module_name = nre.captures(options.get(match))[0]
        echo "check_hot_reload " & module_name
        var frame = new_frame()
        self.reload_module(frame, module_name, read_file(tried.msg))

template eval*(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  self.check_hot_reload()
  expr.evaluator(self, frame, nil, expr)

#################### Expr ########################

proc eval_todo*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  todo()

proc eval_never*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  raise new_exception(types.Exception, "eval_never should never be called.")

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

#################### ExLiteral ###################

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
    data*: seq[Expr]

proc eval_group*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  for item in cast[ExGroup](expr).data.mitems:
    result = self.eval(frame, item)

proc new_ex_group*(): ExGroup =
  result = ExGroup(
    evaluator: eval_group,
  )

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

#################### ExSelf ######################

type
  ExSelf* = ref object of Expr

proc eval_self(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  frame.self

proc new_ex_self*(): ExSelf =
  ExSelf(
    evaluator: eval_self,
  )

#################### ExNsDef #####################

type
  ExNsDef* = ref object of Expr
    name*: MapKey
    value*: Expr

proc eval_ns_def(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExNsDef](expr)
  result = self.eval(frame, e.value)
  frame.ns[e.name] = result

proc new_ex_ns_def*(): ExNsDef =
  result = ExNsDef(
    evaluator: eval_ns_def,
  )

#################### ExGene ######################

type
  ExGene* = ref object of Expr
    `type`*: Expr
    args*: Value        # The unprocessed args
    args_expr*: Expr    # The translated args

#################### ExArguments #################

type
  ExArguments* = ref object of Expr
    props*: Table[MapKey, Expr]
    data*: seq[Expr]

proc eval_args(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  todo()

proc new_ex_arg*(): ExArguments =
  result = ExArguments(
    evaluator: eval_args,
  )

#################### ExBreak #####################

type
  ExBreak* = ref object of Expr

proc eval_break*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e: Break
  e.new
  raise e

proc new_ex_break*(): ExBreak =
  result = ExBreak(
    evaluator: eval_break,
  )

##################################################

type
  ExSymbol* = ref object of Expr
    name*: MapKey

  # Special case
  # ExName* = ref object of Expr
  #   name*: MapKey

  ExNames* = ref object of Expr
    names*: seq[MapKey]

proc eval_names*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExNames](expr)
  case e.names[0]:
  of GLOBAL_KEY:
    result = GLOBAL_NS
  else:
    result = frame.scope[e.names[0]]

  if result == nil:
    result = frame.ns[e.names[0]]
  # for name in e.names[1..^1]:
  #   result = result.get_member(name)

proc new_ex_names*(self: Value): ExNames =
  var e = ExNames(
    evaluator: eval_names,
  )
  for s in self.csymbol:
    e.names.add(s.to_key)
  result = e

#################### ExSetProp ###################

type
  ExSetProp* = ref object of Expr
    name*: MapKey
    value*: Expr

  # ExGetProp* = ref object of Expr
  #   name*: MapKey

proc eval_set_prop*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var value = cast[ExSetProp](expr).value
  result = self.eval(frame, value)
  frame.self.instance_props[cast[ExSetProp](expr).name] = result

proc new_ex_set_prop*(name: string, value: Expr): ExSetProp =
  ExSetProp(
    evaluator: eval_set_prop,
    name: name.to_key,
    value: value,
  )

# proc eval_get_prop*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
#   frame.self.instance_props[cast[ExGetProp](expr).name]

# proc new_ex_get_prop*(name: string): ExGetProp =
#   ExGetProp(
#     evaluator: eval_get_prop,
#     name: name.to_key,
#   )

#################### Selector ####################

type
  ExInvokeSelector* = ref object of Expr
    self*: Expr
    data*: seq[Expr]

##################################################

var Translators*     = Table[ValueKind, Translator]()
var GeneTranslators* = Table[string, Translator]()

##################################################

proc default_translator(value: Value): Expr =
  case value.kind:
  of VkNil, VkBool, VkInt, VkFloat, VkRegex, VkTime:
    return new_ex_literal(value)
  of VkString:
    return new_ex_string(value)
  of VkStream:
    return translate(value.stream)
  else:
    todo($value.kind)

proc translate*(value: Value): Expr =
  var translator = Translators.get_or_default(value.kind, default_translator)
  translator(value)

proc translate*(stmts: seq[Value]): Expr =
  case stmts.len:
  of 0:
    result = new_ex_literal(Nil)
  of 1:
    result = translate(stmts[0])
  else:
    result = new_ex_group()
    for stmt in stmts:
      cast[ExGroup](result).data.add(translate(stmt))

# (@p = 1)
proc translate_prop_assignment*(value: Value): Expr =
  var name = value.gene_type.symbol[1..^1]
  return new_ex_set_prop(name, translate(value.gene_data[1]))
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
      # result.dependencies = parse_deps(doc.props[DEPS_KEY].vec)
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
  self.modules[module.name.to_key] = module
  var frame = new_frame()
  frame.ns = module.ns
  frame.scope = new_scope()
  var code = read_file(file)
  result = self.eval(frame, code)
  if frame.ns.has_key(MAIN_KEY):
    var main = frame[MAIN_KEY]
    if main.kind == VkFunction:
      var args = VM.app.ns[CMD_ARGS_KEY]
      result = self.call_fn(frame, main, args)
    else:
      raise new_exception(CatchableError, "main is not a function.")
  self.wait_for_futures()

proc repl_on_error*(self: VirtualMachine, frame: Frame, e: ref CatchableError): Value =
  echo "An exception was thrown: " & e.msg
  echo "Opening debug console..."
  echo "Note: the exception can be accessed as $ex"
  var ex = error_to_gene(e)
  frame.scope.def_member(CUR_EXCEPTION_KEY, ex)
  result = repl(self, frame, eval, true)

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
  else:
    todo("parse " & $v.kind)

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
  var splat_value = new_gene_map(splat)
  frame.scope.def_member(self.prop_splat, splat_value)
  # TODO: handle @a... or ^@a...

proc match(vm: VirtualMachine, frame: Frame, self: Matcher, input: Value, state: MatchState, r: MatchResult) =
  case self.kind:
  of MatchData:
    var value: Value
    if self.is_splat:
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
      if self.is_prop:
        frame.self.instance_props[self.name] = value
    var child_state = MatchState()
    for child in self.children:
      vm.match(frame, child, value, child_state, r)
    vm.match_prop_splat(frame, self.children, value, r)

  of MatchProp:
    var value: Value
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

  else:
    todo()

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
      new_frame.scope.def_member(field.name, value)
      if field.is_prop:
        new_frame.self.instance_props[field.name] = value
  else:
    var args = new_gene_gene()
    for k, v in args_expr.props.mpairs:
      args.gene_props[k] = self.eval(frame, v)
    for _, v in args_expr.data.mpairs:
      args.gene_data.add self.eval(frame, v)
    self.process_args(new_frame, matcher, args)

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
  except CatchableError as e:
    if self.repl_on_error:
      result = repl_on_error(self, frame, e)
      discard
    else:
      raise
  if target.fn.async and result.kind != VkFuture:
    var future = new_future[Value]()
    future.complete(result)
    result = new_gene_future(future)

proc call_fn*(self: VirtualMachine, frame: Frame, target: Value, args: Value): Value =
  var fn_scope = new_scope()
  fn_scope.set_parent(target.fn.parent_scope, target.fn.parent_scope_max)
  var new_frame = Frame(ns: target.fn.ns, scope: fn_scope)
  new_frame.parent = frame

  self.process_args(new_frame, target.fn.matcher, args)
  self.call_fn_skip_args(new_frame, target)

proc reload_module*(self: VirtualMachine, frame: Frame, name: string, code: string) =
  var loaded_module = self.modules[name.to_key]
  if loaded_module.is_nil:
    not_allowed("reload_module: " & loaded_module.name & " must be imported before being reloaded.")
  elif not loaded_module.reloadable:
    not_allowed("reload_module: " & loaded_module.name & " is not reloadable.")

  proc callback(future: Future[Value]) =
    {.cast(gcsafe).}:
      var module = new_module(name)
      var new_frame = new_frame()
      new_frame.ns = module.ns
      new_frame.scope = new_scope()
      var parsed = self.prepare(code)
      var expr = translate(parsed)
      discard self.eval(new_frame, expr)
      self.modules[name.to_key] = module

  var old_module = self.modules[name.to_key]
  if old_module.on_unloaded != nil:
    var args = new_gene_gene()
    args.gene_data.add(Value(kind: VkModule, module: old_module))
    var unloaded_result = self.call_fn(frame, old_module.on_unloaded, args)
    if unloaded_result != nil and unloaded_result.kind == VkFuture:
      unloaded_result.future.add_callback(callback)
      return

  callback(nil)

import strutils, sequtils, tables, strutils, parsecsv, streams
import os, osproc, json, httpclient, base64, times, dynlib, uri
import asyncdispatch, asyncfile, asynchttpserver

import ./map_key
import ./types
import ./parser
import ./decorator
import ./translators
import ./dynlib_mapping
import ./repl

let GENE_HOME*    = get_env("GENE_HOME", parent_dir(get_app_dir()))
let GENE_RUNTIME* = Runtime(
  home: GENE_HOME,
  name: "default",
  version: read_file(GENE_HOME & "/VERSION").strip(),
)

#################### Definitions #################

proc import_module*(self: VirtualMachine, name: MapKey, code: string): Namespace
proc load_core_module*(self: VirtualMachine)
proc load_gene_module*(self: VirtualMachine)
proc load_genex_module*(self: VirtualMachine)
proc init_native*()
proc def_member*(self: VirtualMachine, frame: Frame, name: MapKey, value: GeneValue, in_ns: bool)
proc def_member*(self: VirtualMachine, frame: Frame, name: GeneValue, value: GeneValue, in_ns: bool)
proc get_member*(self: VirtualMachine, frame: Frame, name: ComplexSymbol): GeneValue
proc set_member*(self: VirtualMachine, frame: Frame, name: GeneValue, value: GeneValue)
proc match*(self: VirtualMachine, frame: Frame, pattern: GeneValue, val: GeneValue, mode: MatchMode): GeneValue
proc import_from_ns*(self: VirtualMachine, frame: Frame, source: GeneValue, group: seq[ImportMatcher])
proc explode_and_add*(parent: GeneValue, value: GeneValue)

proc eval_args*(self: VirtualMachine, frame: Frame, props: seq[Expr], data: seq[Expr]): GeneValue {.inline.}

proc call_method*(self: VirtualMachine, frame: Frame, instance: GeneValue, class: Class, method_name: MapKey, args_blk: seq[Expr]): GeneValue
proc call_method*(self: VirtualMachine, frame: Frame, instance: GeneValue, class: Class, method_name: MapKey, args: GeneValue): GeneValue
proc call_fn*(self: VirtualMachine, frame: Frame, target: GeneValue, fn: Function, args: GeneValue, options: Table[FnOption, GeneValue]): GeneValue
proc call_fn*(self: VirtualMachine, target: GeneValue, fn: Function, args: GeneValue): GeneValue
proc call_macro*(self: VirtualMachine, frame: Frame, target: GeneValue, mac: Macro, expr: Expr): GeneValue
proc call_block*(self: VirtualMachine, frame: Frame, target: GeneValue, blk: Block, expr: Expr): GeneValue

proc call_aspect*(self: VirtualMachine, frame: Frame, aspect: Aspect, expr: Expr): GeneValue
proc call_aspect_instance*(self: VirtualMachine, frame: Frame, instance: AspectInstance, args: GeneValue): GeneValue

#################### Implementations #############

#################### Application #################

proc new_app*(): Application =
  result = Application()
  var global = new_namespace("global")
  result.ns = global
  global[APP_KEY] = result
  global[STDIN_KEY]  = stdin
  global[STDOUT_KEY] = stdout
  global[STDERR_KEY] = stderr
  # Moved to interpreter_extras.nim
  # var cmd_args = command_line_params().map(str_to_gene)
  # global[CMD_ARGS_KEY] = cmd_args

#################### Package #####################

proc parse_deps(deps: seq[GeneValue]): Table[string, Package] =
  for dep in deps:
    var name = dep.gene.data[0].str
    var version = dep.gene.data[1]
    var location = dep.gene.props[LOCATION_KEY]
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
      result.ns[CUR_PKG_KEY] = result
      return result
    else:
      d = parent_dir(d)

  result.adhoc = true
  result.ns = new_namespace(VM.app.ns, "package:<adhoc>")
  result.dir = d
  result.ns[CUR_PKG_KEY] = result

#################### Selectors ###################

let NO_RESULT = new_gene_gene(new_gene_symbol("SELECTOR_NO_RESULT"))

proc search*(self: Selector, target: GeneValue, r: SelectorResult)

proc search_first(self: SelectorMatcher, target: GeneValue): GeneValue =
  case self.kind:
  of SmByIndex:
    case target.kind:
    of GeneVector:
      if self.index >= target.vec.len:
        return NO_RESULT
      else:
        return target.vec[self.index]
    of GeneGene:
      if self.index >= target.gene.data.len:
        return NO_RESULT
      else:
        return target.gene.data[self.index]
    else:
      todo()
  of SmByName:
    case target.kind:
    of GeneMap:
      if target.map.has_key(self.name):
        return target.map[self.name]
      else:
        return NO_RESULT
    of GeneGene:
      if target.gene.props.has_key(self.name):
        return target.gene.props[self.name]
      else:
        return NO_RESULT
    of GeneInternal:
      case target.internal.kind:
      of GeneInstance:
        return target.internal.instance.value.gene.props.get_or_default(self.name, GeneNil)
      else:
        todo($target.internal.kind)
    else:
      todo($target.kind)
  of SmByType:
    case target.kind:
    of GeneVector:
      for item in target.vec:
        if item.kind == GeneGene and item.gene.type == self.by_type:
          return item
    else:
      todo($target.kind)
  else:
    todo()

proc add_self_and_descendants(self: var seq[GeneValue], v: GeneValue) =
  self.add(v)
  case v.kind:
  of GeneVector:
    for child in v.vec:
      self.add_self_and_descendants(child)
  of GeneGene:
    for child in v.gene.data:
      self.add_self_and_descendants(child)
  else:
    discard

proc search(self: SelectorMatcher, target: GeneValue): seq[GeneValue] =
  case self.kind:
  of SmByIndex:
    case target.kind:
    of GeneVector:
      result.add(target.vec[self.index])
    of GeneGene:
      result.add(target.gene.data[self.index])
    else:
      todo()
  of SmByName:
    case target.kind:
    of GeneMap:
      result.add(target.map[self.name])
    else:
      todo()
  of SmByType:
    case target.kind:
    of GeneVector:
      for item in target.vec:
        if item.kind == GeneGene and item.gene.type == self.by_type:
          result.add(item)
    of GeneGene:
      for item in target.gene.data:
        if item.kind == GeneGene and item.gene.type == self.by_type:
          result.add(item)
    else:
      discard
  of SmSelfAndDescendants:
    result.add_self_and_descendants(target)
  of SmCallback:
    var args = new_gene_gene(GeneNil)
    args.gene.data.add(target)
    var v = VM.call_fn(GeneNil, self.callback.internal.fn, args)
    if v.kind == GeneGene and v.gene.type.kind == GeneSymbol:
      case v.gene.type.symbol:
      of "void":
        discard
      else:
        result.add(v)
    else:
      result.add(v)
  else:
    todo()

proc search(self: SelectorItem, target: GeneValue, r: SelectorResult) =
  case self.kind:
  of SiDefault:
    if self.is_last():
      case r.mode:
      of SrFirst:
        for m in self.matchers:
          var v = m.search_first(target)
          if v != NO_RESULT:
            r.done = true
            r.first = v
            break
      of SrAll:
        for m in self.matchers:
          r.all.add(m.search(target))
    else:
      var items: seq[GeneValue] = @[]
      for m in self.matchers:
        try:
          items.add(m.search(target))
        except SelectorNoResult:
          discard
      for child in self.children:
        for item in items:
          child.search(item, r)
  of SiSelector:
    self.selector.search(target, r)

proc search(self: Selector, target: GeneValue, r: SelectorResult) =
  case r.mode:
  of SrFirst:
    for child in self.children:
      child.search(target, r)
      if r.done:
        return
  else:
    for child in self.children:
      child.search(target, r)

proc search*(self: Selector, target: GeneValue): GeneValue =
  if self.is_singular():
    var r = SelectorResult(mode: SrFirst)
    self.search(target, r)
    if r.done:
      result = r.first
      # TODO: invoke callbacks
    else:
      raise new_exception(SelectorNoResult, "No result is found for the selector.")
  else:
    var r = SelectorResult(mode: SrAll)
    self.search(target, r)
    result = new_gene_vec(r.all)
    # TODO: invoke callbacks

proc update(self: SelectorItem, target: GeneValue, value: GeneValue): bool =
  for m in self.matchers:
    case m.kind:
    of SmByIndex:
      case target.kind:
      of GeneVector:
        if self.is_last:
          target.vec[m.index] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.vec[m.index], value)
      else:
        todo()
    of SmByName:
      case target.kind:
      of GeneMap:
        if self.is_last:
          target.map[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.map[m.name], value)
      of GeneGene:
        if self.is_last:
          target.gene.props[m.name] = value
          result = true
        else:
          for child in self.children:
            result = result or child.update(target.gene.props[m.name], value)
      of GeneInternal:
        case target.internal.kind:
        of GeneInstance:
          var g = target.internal.instance.value.gene
          if self.is_last:
            g.props[m.name] = value
            result = true
          else:
            for child in self.children:
              result = result or child.update(g.props[m.name], value)
        else:
          todo()
      else:
        todo($target.kind)
    else:
      todo()

proc update*(self: Selector, target: GeneValue, value: GeneValue): bool =
  for child in self.children:
    result = result or child.update(target, value)

#################### VM ##########################

proc new_vm*(app: Application): VirtualMachine =
  result = VirtualMachine(
    app: app,
  )

proc init_app_and_vm*() =
  var app = new_app()
  VM = new_vm(app)

proc wait_for_futures*(self: VirtualMachine) =
  try:
    run_forever()
  except ValueError as e:
    if e.msg == "No handles or timers registered in dispatcher.":
      discard
    else:
      raise

proc prepare*(self: VirtualMachine, code: string): Expr =
  var parsed = process_decorators(read_all(code))
  result = Expr(
    kind: ExRoot,
  )
  result.root = new_group_expr(result, parsed)

const DRAIN_MAX = 15
var drain_count = 0
proc drain() {.inline.} =
  if drain_count < DRAIN_MAX:
    drain_count += 1
  else:
    drain_count = 0
    if hasPendingOperations():
      drain(0)

proc eval*(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  if expr.evaluator != nil:
    result = expr.evaluator(self, frame, expr)
  else:
    var evaluator = EvaluatorMgr[expr.kind]
    expr.evaluator = evaluator
    result = evaluator(self, frame, expr)

  drain()
  if result == nil:
    return GeneNil
  else:
    return result

proc eval_prepare*(self: VirtualMachine): Frame =
  var module = new_module()
  return FrameMgr.get(FrModule, module.root_ns, new_scope())

proc eval_only*(self: VirtualMachine, frame: Frame, code: string): GeneValue =
  result = self.eval(frame, self.prepare(code))
  drain(0)

proc eval*(self: VirtualMachine, code: string): GeneValue =
  var module = new_module()
  var frame = FrameMgr.get(FrModule, module.root_ns, new_scope())
  result = self.eval(frame, self.prepare(code))
  drain(0)

proc init_package*(self: VirtualMachine, dir: string) =
  self.app.pkg = new_package(dir)

proc run_file*(self: VirtualMachine, file: string): GeneValue =
  var module = new_module(self.app.pkg.ns, file)
  var frame = FrameMgr.get(FrModule, module.root_ns, new_scope())
  var code = read_file(file)
  discard self.eval(frame, self.prepare(code))
  if frame.ns.has_key(MAIN_KEY):
    var main = frame[MAIN_KEY]
    if main.kind == GeneInternal and main.internal.kind == GeneFunction:
      var args = VM.app.ns[CMD_ARGS_KEY]
      var options = Table[FnOption, GeneValue]()
      result = self.call_fn(frame, GeneNil, main.internal.fn, args, options)
    else:
      raise new_exception(CatchableError, "main is not a function.")
  self.wait_for_futures()

proc import_module*(self: VirtualMachine, name: MapKey, code: string): Namespace =
  if self.modules.has_key(name):
    return self.modules[name]
  var module = new_module(name.to_s)
  var frame = FrameMgr.get(FrModule, module.root_ns, new_scope())
  self.def_member(frame, FILE_KEY, name.to_s, true)
  discard self.eval(frame, self.prepare(code))
  result = module.root_ns
  self.modules[name] = result

proc load_core_module*(self: VirtualMachine) =
  VM.gene_ns  = new_namespace("gene")
  VM.app.ns[GENE_KEY] = VM.gene_ns
  VM.genex_ns = new_namespace("genex")
  VM.app.ns[GENEX_KEY] = VM.genex_ns
  VM.gene_ns.internal.ns[NATIVE_KEY] = new_namespace("native")
  init_native()
  discard self.import_module(CORE_KEY, readFile(GENE_HOME & "/src/core.gene"))

proc load_gene_module*(self: VirtualMachine) =
  discard self.import_module(GENE_KEY, readFile(GENE_HOME & "/src/gene.gene"))
  GeneObjectClass    = VM.gene_ns[OBJECT_CLASS_KEY]
  GeneClassClass     = VM.gene_ns[CLASS_CLASS_KEY]
  GeneExceptionClass = VM.gene_ns[EXCEPTION_CLASS_KEY]

proc load_genex_module*(self: VirtualMachine) =
  discard self.import_module(GENEX_KEY, readFile(GENE_HOME & "/src/genex.gene"))

proc call_method*(self: VirtualMachine, frame: Frame, instance: GeneValue, class: Class, method_name: MapKey, args: GeneValue): GeneValue =
  var meth = class.get_method(method_name)
  if meth != nil:
    var options = Table[FnOption, GeneValue]()
    options[FnClass] = class
    options[FnMethod] = meth
    if meth.fn == nil:
      result = meth.fn_native(instance, args.gene.props, args.gene.data)
    else:
      result = self.call_fn(frame, instance, meth.fn, args, options)
  else:
    if method_name == NEW_KEY: # No implementation is required for `new` method
      discard
    else:
      todo("Method is missing: " & method_name.to_s)

proc call_method*(self: VirtualMachine, frame: Frame, instance: GeneValue, class: Class, method_name: MapKey, args_blk: seq[Expr]): GeneValue =
  var args = self.eval_args(frame, @[], args_blk)
  result = self.call_method(frame, instance, class, method_name, args)

proc eval_args*(self: VirtualMachine, frame: Frame, props: seq[Expr], data: seq[Expr]): GeneValue {.inline.} =
  result = new_gene_gene(GeneNil)
  for e in props:
    var v = self.eval(frame, e)
    result.gene.props[e.map_key] = v
  for e in data:
    var v = self.eval(frame, e)
    if v.kind == GeneInternal and v.internal.kind == GeneExplode:
      result.merge(v.internal.explode)
    else:
      result.gene.data.add(v)

proc process_args*(self: VirtualMachine, frame: Frame, matcher: RootMatcher, args: GeneValue) =
  var match_result = matcher.match(args)
  case match_result.kind:
  of MatchSuccess:
    for field in match_result.fields:
      if field.value_expr != nil:
        frame.scope.def_member(field.name, self.eval(frame, field.value_expr))
      else:
        frame.scope.def_member(field.name, field.value)
  of MatchMissingFields:
    for field in match_result.missing:
      not_allowed("Argument " & field.to_s & " is missing.")
  else:
    todo()

proc repl_on_error(self: VirtualMachine, frame: Frame, e: ref CatchableError): GeneValue =
  echo "An exception was thrown: " & e.msg
  echo "Opening debug console..."
  echo "Note: the exception can be accessed as $ex"
  var ex = error_to_gene(e)
  self.def_member(frame, CUR_EXCEPTION_KEY, ex, false)
  result = repl(self, frame, eval_only, true)

proc call_fn_internal*(
  self: VirtualMachine,
  frame: Frame,
  target: GeneValue,
  fn: Function,
  args: GeneValue,
  options: Table[FnOption, GeneValue]
): GeneValue =
  var ns: Namespace = fn.ns
  var fn_scope = new_scope()
  if fn.expr.kind == ExFn:
    fn_scope.set_parent(fn.parent_scope, fn.parent_scope_max)
  var new_frame: Frame
  if options.has_key(FnMethod):
    new_frame = FrameMgr.get(FrMethod, ns, fn_scope)
    fn_scope.def_member(CLASS_OPTION_KEY, options[FnClass])
    var meth = options[FnMethod]
    fn_scope.def_member(METHOD_OPTION_KEY, meth)
  else:
    new_frame = FrameMgr.get(FrFunction, ns, fn_scope)
  new_frame.parent = frame
  new_frame.self = target

  new_frame.args = args
  self.process_args(new_frame, fn.matcher, new_frame.args)

  if fn.body_blk.len == 0:  # Translate on demand
    for item in fn.body:
      fn.body_blk.add(new_expr(fn.expr, item))
  try:
    for e in fn.body_blk:
      result = self.eval(new_frame, e)
  except Return as r:
    # return's frame is the same as new_frame(current function's frame)
    if r.frame == new_frame:
      result = r.val
    else:
      raise
  except CatchableError as e:
    if self.repl_on_error:
      result = repl_on_error(self, frame, e)
    else:
      raise

proc call_fn*(
  self: VirtualMachine,
  frame: Frame,
  target: GeneValue,
  fn: Function,
  args: GeneValue,
  options: Table[FnOption, GeneValue]
): GeneValue =
  if fn.async:
    try:
      var val = self.call_fn_internal(frame, target, fn, args, options)
      if val.kind == GeneInternal and val.internal.kind == GeneFuture:
        return val
      var future = new_future[GeneValue]()
      future.complete(val)
      result = future_to_gene(future)
    except CatchableError as e:
      var future = new_future[GeneValue]()
      future.fail(e)
      result = future_to_gene(future)
  else:
    return self.call_fn_internal(frame, target, fn, args, options)

proc call_fn*(
  self: VirtualMachine,
  target: GeneValue,
  fn: Function,
  args: GeneValue,
): GeneValue =
  var ns = VM.app.ns
  var scope = new_scope()
  var frame = FrameMgr.get(FrBody, ns, scope)
  frame.args = args
  var options = Table[FnOption, GeneValue]()
  self.call_fn(frame, target, fn, args, options)

proc call_macro*(self: VirtualMachine, frame: Frame, target: GeneValue, mac: Macro, expr: Expr): GeneValue =
  var mac_scope = new_scope()
  var new_frame = FrameMgr.get(FrFunction, mac.ns, mac_scope)
  new_frame.parent = frame
  new_frame.self = target

  new_frame.args = expr.gene
  self.process_args(new_frame, mac.matcher, new_frame.args)

  var blk: seq[Expr] = @[]
  for item in mac.body:
    blk.add(new_expr(mac.expr, item))
  try:
    for e in blk:
      result = self.eval(new_frame, e)
  except Return as r:
    result = r.val
  except CatchableError as e:
    if self.repl_on_error:
      result = repl_on_error(self, frame, e)
    else:
      raise

proc call_block*(self: VirtualMachine, frame: Frame, target: GeneValue, blk: Block, args: GeneValue): GeneValue =
  var blk_scope = new_scope()
  blk_scope.set_parent(blk.frame.scope, blk.parent_scope_max)
  var new_frame = blk.frame
  self.process_args(new_frame, blk.matcher, args)

  var blk2: seq[Expr] = @[]
  for item in blk.body:
    blk2.add(new_expr(blk.expr, item))
  try:
    for e in blk2:
      result = self.eval(new_frame, e)
  except Return, Break:
    raise
  except CatchableError as e:
    if self.repl_on_error:
      result = repl_on_error(self, frame, e)
    else:
      raise

proc call_block*(self: VirtualMachine, frame: Frame, target: GeneValue, blk: Block, expr: Expr): GeneValue =
  var args_blk: seq[Expr]
  case expr.kind:
  of ExGene:
    args_blk = expr.gene_data
  else:
    args_blk = @[]

  var args = new_gene_gene(GeneNil)
  for e in args_blk:
    var v = self.eval(frame, e)
    if v.kind == GeneInternal and v.internal.kind == GeneExplode:
      args.merge(v.internal.explode)
    else:
      args.gene.data.add(v)

  result = self.call_block(frame, target, blk, args)

proc call_aspect*(self: VirtualMachine, frame: Frame, aspect: Aspect, expr: Expr): GeneValue =
  var new_scope = new_scope()
  var new_frame = FrameMgr.get(FrBody, aspect.ns, new_scope)
  new_frame.parent = frame

  new_frame.args = new_gene_gene(GeneNil)
  for e in expr.gene_data:
    var v = self.eval(frame, e)
    if v.kind == GeneInternal and v.internal.kind == GeneExplode:
      new_frame.args.merge(v.internal.explode)
    else:
      new_frame.args.gene.data.add(v)
  self.process_args(new_frame, aspect.matcher, new_frame.args)

  var target = new_frame.args[0]
  result = new_aspect_instance(aspect, target)
  new_frame.self = result

  var blk: seq[Expr] = @[]
  for item in aspect.body:
    blk.add(new_expr(aspect.expr, item))
  try:
    for e in blk:
      discard self.eval(new_frame, e)
  except Return:
    discard

proc call_aspect_instance*(self: VirtualMachine, frame: Frame, instance: AspectInstance, args: GeneValue): GeneValue =
  var aspect = instance.aspect
  var new_scope = new_scope()
  var new_frame = FrameMgr.get(FrBody, aspect.ns, new_scope)
  new_frame.parent = frame
  new_frame.args = args

  # invoke before advices
  var options = Table[FnOption, GeneValue]()
  for advice in instance.before_advices:
    discard self.call_fn(new_frame, frame.self, advice.logic, new_frame.args, options)

  # invoke target
  case instance.target.internal.kind:
  of GeneFunction:
    result = self.call_fn(new_frame, frame.self, instance.target, new_frame.args, options)
  of GeneAspectInstance:
    result = self.call_aspect_instance(new_frame, instance.target.internal.aspect_instance, new_frame.args)
  else:
    todo()

  # invoke after advices
  for advice in instance.after_advices:
    discard self.call_fn(new_frame, frame.self, advice.logic, new_frame.args, options)

proc call_target*(self: VirtualMachine, frame: Frame, target: GeneValue, args: GeneValue, expr: Expr): GeneValue =
  case target.kind:
  of GeneInternal:
    case target.internal.kind:
    of GeneFunction:
      var options = Table[FnOption, GeneValue]()
      result = self.call_fn(frame, GeneNil, target.internal.fn, args, options)
    of GeneBlock:
      result = self.call_block(frame, GeneNil, target.internal.blk, args)
    else:
      todo()
  else:
    todo()

proc def_member*(self: VirtualMachine, frame: Frame, name: MapKey, value: GeneValue, in_ns: bool) =
  if in_ns:
    frame.ns[name] = value
  else:
    frame.scope.def_member(name, value)

proc def_member*(self: VirtualMachine, frame: Frame, name: GeneValue, value: GeneValue, in_ns: bool) =
  case name.kind:
  of GeneString:
    if in_ns:
      frame.ns[name.str.to_key] = value
    else:
      frame.scope.def_member(name.str.to_key, value)
  of GeneSymbol:
    if in_ns:
      frame.ns[name.symbol.to_key] = value
    else:
      frame.scope.def_member(name.symbol.to_key, value)
  of GeneComplexSymbol:
    var ns: Namespace
    case name.csymbol.first:
    of "global":
      ns = VM.app.ns
    of "gene":
      ns = VM.gene_ns.internal.ns
    of "genex":
      ns = VM.genex_ns.internal.ns
    of "":
      ns = frame.ns
    else:
      var s = name.csymbol.first
      ns = frame[s.to_key].internal.ns
    for i in 0..<(name.csymbol.rest.len - 1):
      var name = name.csymbol.rest[i]
      ns = ns[name.to_key].internal.ns
    var base_name = name.csymbol.rest[^1]
    ns[base_name.to_key] = value
  else:
    not_allowed()

proc get_member*(self: VirtualMachine, frame: Frame, name: ComplexSymbol): GeneValue =
  if name.first == "global":
    result = VM.app.ns
  elif name.first == "gene":
    result = VM.gene_ns
  elif name.first == "genex":
    result = VM.genex_ns
  elif name.first == "":
    result = frame.ns
  else:
    result = frame[name.first.to_key]
  for name in name.rest:
    result = result.get_member(name)

proc set_member*(self: VirtualMachine, frame: Frame, name: GeneValue, value: GeneValue) =
  case name.kind:
  of GeneSymbol:
    if frame.scope.has_key(name.symbol.to_key):
      frame.scope[name.symbol.to_key] = value
    else:
      frame.ns[name.symbol.to_key] = value
  of GeneComplexSymbol:
    var ns: Namespace
    case name.csymbol.first:
    of "global":
      ns = VM.app.ns
    of "gene":
      ns = VM.gene_ns.internal.ns
    of "genex":
      ns = VM.genex_ns.internal.ns
    of "":
      ns = frame.ns
    else:
      var s = name.csymbol.first
      ns = frame[s.to_key].internal.ns
    for i in 0..<(name.csymbol.rest.len - 1):
      var name = name.csymbol.rest[i]
      ns = ns[name.to_key].internal.ns
    var base_name = name.csymbol.rest[^1]
    ns[base_name.to_key] = value
  else:
    not_allowed()

proc match*(self: VirtualMachine, frame: Frame, pattern: GeneValue, val: GeneValue, mode: MatchMode): GeneValue =
  case pattern.kind:
  of GeneSymbol:
    var name = pattern.symbol
    case mode:
    of MatchArgs:
      frame.scope.def_member(name.to_key, val.gene.data[0])
    else:
      frame.scope.def_member(name.to_key, val)
  of GeneVector:
    for i in 0..<pattern.vec.len:
      var name = pattern.vec[i].symbol
      if i < val.gene.data.len:
        frame.scope.def_member(name.to_key, val.gene.data[i])
      else:
        frame.scope.def_member(name.to_key, GeneNil)
  else:
    todo()

proc import_from_ns*(self: VirtualMachine, frame: Frame, source: GeneValue, group: seq[ImportMatcher]) =
  for m in group:
    if m.name == MUL_KEY:
      for k, v in source.internal.ns.members:
        self.def_member(frame, k, v, true)
    else:
      var value = source.internal.ns[m.name]
      if m.children_only:
        self.import_from_ns(frame, value.internal.ns, m.children)
      else:
        self.def_member(frame, m.name, value, true)

proc explode_and_add*(parent: GeneValue, value: GeneValue) =
  if value.kind == GeneInternal and value.internal.kind == GeneExplode:
    var explode = value.internal.explode
    case parent.kind:
    of GeneVector:
      case explode.kind:
      of GeneVector:
        for item in explode.vec:
          parent.vec.add(item)
      else:
        todo()
    of GeneGene:
      case explode.kind:
      of GeneVector:
        for item in explode.vec:
          parent.vec.add(item)
      else:
        todo()
    else:
      todo()
  else:
    case parent.kind:
    of GeneVector:
      parent.vec.add(value)
    of GeneGene:
      parent.gene.data.add(value)
    else:
      todo()

EvaluatorMgr[ExTodo] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  if expr.todo != nil:
    todo(self.eval(frame, expr.todo).str)
  else:
    todo()

EvaluatorMgr[ExNotAllowed] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  if expr.not_allowed != nil:
    not_allowed(self.eval(frame, expr.not_allowed).str)
  else:
    not_allowed()

EvaluatorMgr[ExSymbol] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  case expr.symbol_kind:
  of SkUnknown:
    var e = expr
    if expr.symbol == GENE_KEY:
      e.symbol_kind = SkGene
      return VM.gene_ns
    elif expr.symbol == GENEX_KEY:
      e.symbol_kind = SkGenex
      return VM.genex_ns
    else:
      result = frame.scope[expr.symbol]
      if result != nil:
        e.symbol_kind = SkScope
      else:
        var pair = frame.ns.locate(expr.symbol)
        e.symbol_kind = SkNamespace
        e.symbol_ns = pair[1]
        result = pair[0]
  of SkGene:
    result = VM.gene_ns
  of SkGenex:
    result = VM.genex_ns
  of SkNamespace:
    result = expr.symbol_ns[expr.symbol]
  of SkScope:
    result = frame.scope[expr.symbol]

EvaluatorMgr[ExDo] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var old_self = frame.self
  try:
    for e in expr.do_props:
      var val = self.eval(frame, e)
      if e.map_key == SELF_KEY:
        frame.self = val
      else:
        todo()
    for e in expr.do_body:
      result = self.eval(frame, e)
      if result.kind == GeneInternal and result.internal.kind == GeneExplode:
        for item in result.internal.explode.vec:
          result = self.eval(frame, new_expr(e, item))
  finally:
    frame.self = old_self

EvaluatorMgr[ExGroup] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  for e in expr.group:
    result = self.eval(frame, e)

EvaluatorMgr[ExArray] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  result = new_gene_vec()
  for e in expr.array:
    result.explode_and_add(self.eval(frame, e))

EvaluatorMgr[ExMap] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  result = new_gene_map()
  for e in expr.map:
    result.map[e.map_key] = self.eval(frame, e.map_val)

EvaluatorMgr[ExMapChild] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  result = self.eval(frame, expr.map_val)
  # Assign the value to map/gene should be handled by evaluation of parent expression

EvaluatorMgr[ExGet] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var target = self.eval(frame, expr.get_target)
  var index = self.eval(frame, expr.get_index)
  result = target.gene.data[index.int]

EvaluatorMgr[ExSet] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var target = self.eval(frame, expr.set_target)
  var index = self.eval(frame, expr.set_index)
  var value = self.eval(frame, expr.set_value)
  if index.kind == GeneInternal and index.internal.kind == GeneSelector:
    var success = index.internal.selector.update(target, value)
    if not success:
      todo("Update by selector failed.")
  else:
    target.gene.data[index.int] = value

EvaluatorMgr[ExDefMember] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var name = self.eval(frame, expr.def_member_name).symbol_or_str
  var value = self.eval(frame, expr.def_member_value)
  frame.scope.def_member(name.to_key, value)

EvaluatorMgr[ExDefNsMember] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var name = self.eval(frame, expr.def_ns_member_name).symbol_or_str
  var value = self.eval(frame, expr.def_ns_member_value)
  frame.ns[name.to_key] = value

EvaluatorMgr[ExRange] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var range_start = self.eval(frame, expr.range_start)
  var range_end = self.eval(frame, expr.range_end)
  result = new_gene_range(range_start, range_end)

EvaluatorMgr[ExNot] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  result = not self.eval(frame, expr.not)

proc bin_add(self: VirtualMachine, frame: Frame, first, second: GeneValue): GeneValue {.inline.} =
  case first.kind:
  of GeneInt:
    case second.kind:
    of GeneInt:
      result = new_gene_int(first.int + second.int)
    else:
      todo()
  else:
    var class = first.get_class()
    var args = new_gene_gene(GeneNil)
    args.gene.data.add(second)
    result = self.call_method(frame, first, class, ADD_KEY, args)

proc bin_sub(self: VirtualMachine, frame: Frame, first, second: GeneValue): GeneValue {.inline.} =
  case first.kind:
  of GeneInt:
    case second.kind:
    of GeneInt:
      result = new_gene_int(first.int - second.int)
    else:
      todo()
  else:
    var class = first.get_class()
    var args = new_gene_gene(GeneNil)
    args.gene.data.add(second)
    result = self.call_method(frame, first, class, SUB_KEY, args)

EvaluatorMgr[ExBinary] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var first = self.eval(frame, expr.bin_first)
  var second = self.eval(frame, expr.bin_second)
  case expr.bin_op:
  of BinAdd: result = bin_add(self, frame, first, second)
  of BinSub: result = bin_sub(self, frame, first, second)
  of BinMul: result = new_gene_int(first.int * second.int)
  of BinDiv: result = new_gene_float(first.int / second.int)
  of BinEq:  result = new_gene_bool(first == second)
  of BinNeq: result = new_gene_bool(first != second)
  of BinLt:  result = new_gene_bool(first.int < second.int)
  of BinLe:  result = new_gene_bool(first.int <= second.int)
  of BinGt:  result = new_gene_bool(first.int > second.int)
  of BinGe:  result = new_gene_bool(first.int >= second.int)
  of BinAnd: result = new_gene_bool(first.bool and second.bool)
  of BinOr:  result = new_gene_bool(first.bool or second.bool)

EvaluatorMgr[ExBinImmediate] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var first = self.eval(frame, expr.bini_first)
  var second = expr.bini_second
  case expr.bini_op:
  of BinAdd: result = new_gene_int(first.int + second.int)
  of BinSub: result = new_gene_int(first.int - second.int)
  of BinMul: result = new_gene_int(first.int * second.int)
  of BinDiv: result = new_gene_float(first.int / second.int)
  of BinEq:  result = new_gene_bool(first == second)
  of BinNeq: result = new_gene_bool(first != second)
  of BinLt:  result = new_gene_bool(first.int < second.int)
  of BinLe:  result = new_gene_bool(first.int <= second.int)
  of BinGt:  result = new_gene_bool(first.int > second.int)
  of BinGe:  result = new_gene_bool(first.int >= second.int)
  of BinAnd: result = new_gene_bool(first.bool and second.bool)
  of BinOr:  result = new_gene_bool(first.bool or second.bool)

EvaluatorMgr[ExBinAssignment] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var first = frame[expr.bina_first]
  var second = self.eval(frame, expr.bina_second)
  case expr.bina_op:
  of BinAdd: result = bin_add(self, frame, first, second)
  of BinSub: result = bin_sub(self, frame, first, second)
  of BinMul: result = new_gene_int(first.int * second.int)
  of BinDiv: result = new_gene_float(first.int / second.int)
  else: todo()
  self.set_member(frame, expr.bina_first, result)

EvaluatorMgr[ExVar] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var val = self.eval(frame, expr.var_val)
  self.def_member(frame, expr.var_name, val, false)
  result = GeneNil

EvaluatorMgr[ExAssignment] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  result = self.eval(frame, expr.var_val)
  self.set_member(frame, expr.var_name, result)

EvaluatorMgr[ExIf] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var v = self.eval(frame, expr.if_cond)
  if v:
    result = self.eval(frame, expr.if_then)
  elif expr.if_elifs.len > 0:
    for pair in expr.if_elifs:
      if self.eval(frame, pair[0]):
        return self.eval(frame, pair[1])
  elif expr.if_else != nil:
    result = self.eval(frame, expr.if_else)

EvaluatorMgr[ExLoop] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  try:
    while true:
      try:
        for e in expr.loop_blk:
          discard self.eval(frame, e)
      except Continue:
        discard
  except Break as b:
    result = b.val

EvaluatorMgr[ExBreak] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var val = GeneNil
  if expr.break_val != nil:
    val = self.eval(frame, expr.break_val)
  var e: Break
  e.new
  e.val = val
  raise e

EvaluatorMgr[ExContinue] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var e: Continue
  e.new
  raise e

EvaluatorMgr[ExWhile] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  try:
    var cond = self.eval(frame, expr.while_cond)
    while cond:
      try:
        for e in expr.while_blk:
          discard self.eval(frame, e)
      except Continue:
        discard
      cond = self.eval(frame, expr.while_cond)
  except Break as b:
    result = b.val


EvaluatorMgr[ExExplode] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var val = self.eval(frame, expr.explode)
  result = new_gene_explode(val)

EvaluatorMgr[ExThrow] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  if expr.throw_type != nil:
    var class = self.eval(frame, expr.throw_type)
    if expr.throw_mesg != nil:
      var message = self.eval(frame, expr.throw_mesg)
      var instance = new_instance(class.internal.class)
      raise new_gene_exception(message.str, instance)
    elif class.kind == GeneInternal and class.internal.kind == GeneClass:
      var instance = new_instance(class.internal.class)
      raise new_gene_exception(instance)
    elif class.kind == GeneInternal and class.internal.kind == GeneExceptionKind:
      raise class.internal.exception
    elif class.kind == GeneString:
      var instance = new_instance(GeneExceptionClass.internal.class)
      raise new_gene_exception(class.str, instance)
    else:
      todo()
  else:
    # Create instance of gene/Exception
    var class = GeneExceptionClass
    var instance = new_instance(class.internal.class)
    # Create nim exception of GeneException type
    raise new_gene_exception(instance)

EvaluatorMgr[ExTry] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  try:
    for e in expr.try_body:
      result = self.eval(frame, e)
  except GeneException as ex:
    self.def_member(frame, CUR_EXCEPTION_KEY, error_to_gene(ex), false)
    var handled = false
    if expr.try_catches.len > 0:
      for catch in expr.try_catches:
        # check whether the thrown exception matches exception in catch statement
        var class = self.eval(frame, catch[0])
        if class == GenePlaceholder:
          # class = GeneExceptionClass
          handled = true
          for e in catch[1]:
            result = self.eval(frame, e)
          break
        if ex.instance == nil:
          raise
        if ex.instance.is_a(class.internal.class):
          handled = true
          for e in catch[1]:
            result = self.eval(frame, e)
          break
    for e in expr.try_finally:
      try:
        discard self.eval(frame, e)
      except Return, Break:
        discard
    if not handled:
      raise

EvaluatorMgr[ExAwait] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  if expr.await.len == 1:
    var r = self.eval(frame, expr.await[0])
    if r.kind == GeneInternal and r.internal.kind == GeneFuture:
      result = wait_for(r.internal.future)
    else:
      todo()
  else:
    result = new_gene_vec()
    for item in expr.await:
      var r = self.eval(frame, item)
      if r.kind == GeneInternal and r.internal.kind == GeneFuture:
        result.vec.add(wait_for(r.internal.future))
      else:
        todo()

EvaluatorMgr[ExFn] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  expr.fn.internal.fn.ns = frame.ns
  expr.fn.internal.fn.parent_scope = frame.scope
  expr.fn.internal.fn.parent_scope_max = frame.scope.max
  self.def_member(frame, expr.fn_name, expr.fn, true)
  result = expr.fn

EvaluatorMgr[ExArgs] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  case frame.extra.kind:
  of FrFunction, FrMacro, FrMethod:
    result = frame.args
  else:
    not_allowed()

EvaluatorMgr[ExMacro] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  expr.mac.internal.mac.ns = frame.ns
  self.def_member(frame, expr.mac_name, expr.mac, true)
  result = expr.mac

EvaluatorMgr[ExBlock] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  expr.blk.internal.blk.frame = frame
  expr.blk.internal.blk.parent_scope_max = frame.scope.max
  result = expr.blk

EvaluatorMgr[ExReturn] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var val = GeneNil
  if expr.return_val != nil:
    val = self.eval(frame, expr.return_val)
  raise Return(
    frame: frame,
    val: val,
  )

EvaluatorMgr[ExReturnRef] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  result = Return(frame: frame)

EvaluatorMgr[ExAspect] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var aspect = expr.aspect.internal.aspect
  aspect.ns = frame.ns
  frame.ns[aspect.name.to_key] = expr.aspect
  result = expr.aspect

EvaluatorMgr[ExAdvice] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var instance = frame.self.internal.aspect_instance
  var advice: Advice
  var logic = self.eval(frame, new_expr(expr, expr.advice.gene.data[1]))
  case expr.advice.gene.type.symbol:
  of "before":
    advice = new_advice(AdBefore, logic.internal.fn)
    instance.before_advices.add(advice)
  of "after":
    advice = new_advice(AdAfter, logic.internal.fn)
    instance.after_advices.add(advice)
  else:
    todo()
  advice.owner = instance

EvaluatorMgr[ExNamespace] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  expr.ns.internal.ns.parent = frame.ns
  self.def_member(frame, expr.ns_name, expr.ns, true)
  var old_self = frame.self
  var old_ns = frame.ns
  try:
    frame.self = expr.ns
    frame.ns = expr.ns.internal.ns
    for e in expr.ns_body:
      discard self.eval(frame, e)
    result = expr.ns
  finally:
    frame.self = old_self
    frame.ns = old_ns

EvaluatorMgr[ExSelf] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  return frame.self

EvaluatorMgr[ExGlobal] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  return self.app.ns

EvaluatorMgr[ExImport] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var ns: Namespace
  var dir = ""
  if frame.ns.has_key(PKG_KEY):
    var pkg = frame.ns[PKG_KEY].internal.pkg
    dir = pkg.dir & "/"
  # TODO: load import_pkg on demand
  # Set dir to import_pkg's root directory

  var `from` = expr.import_from
  if expr.import_native:
    var path = self.eval(frame, `from`).str
    let lib = load_dynlib(dir & path)
    if lib == nil:
      todo()
    else:
      for m in expr.import_matcher.children:
        var v = lib.sym_addr(m.name.to_s)
        if v == nil:
          todo()
        else:
          self.def_member(frame, m.name, new_gene_internal(cast[NativeFn](v)), true)
  else:
    # If "from" is not given, import from parent of root namespace.
    if `from` == nil:
      ns = frame.ns.root.parent
    else:
      var `from` = self.eval(frame, `from`).str
      if self.modules.has_key(`from`.to_key):
        ns = self.modules[`from`.to_key]
      else:
        var code = read_file(dir & `from` & ".gene")
        ns = self.import_module(`from`.to_key, code)
        self.modules[`from`.to_key] = ns
    self.import_from_ns(frame, ns, expr.import_matcher.children)

EvaluatorMgr[ExIncludeFile] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var file = self.eval(frame, expr.include_file).str
  result = self.eval_only(frame, read_file(file))

EvaluatorMgr[ExStopInheritance] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  frame.ns.stop_inheritance = true

EvaluatorMgr[ExClass] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  expr.class.internal.class.ns.parent = frame.ns
  var super_class: Class
  if expr.super_class == nil:
    if VM.gene_ns != nil and VM.gene_ns.internal.ns.has_key(OBJECT_CLASS_KEY):
      super_class = VM.gene_ns.internal.ns[OBJECT_CLASS_KEY].internal.class
  else:
    super_class = self.eval(frame, expr.super_class).internal.class
  expr.class.internal.class.parent = super_class
  self.def_member(frame, expr.class_name, expr.class, true)
  var ns = expr.class.internal.class.ns
  var scope = new_scope()
  var new_frame = FrameMgr.get(FrBody, ns, scope)
  new_frame.self = expr.class
  for e in expr.class_body:
    discard self.eval(new_frame, e)
  result = expr.class

EvaluatorMgr[ExObject] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var name = expr.obj_name
  var s: string
  case name.kind:
  of GeneSymbol:
    s = name.symbol
  of GeneComplexSymbol:
    s = name.csymbol.rest[^1]
  else:
    not_allowed()
  var class = new_class(s & "Class")
  class.ns.parent = frame.ns
  var super_class: Class
  if expr.obj_super_class == nil:
    if VM.gene_ns != nil and VM.gene_ns.internal.ns.has_key(OBJECT_CLASS_KEY):
      super_class = VM.gene_ns.internal.ns[OBJECT_CLASS_KEY].internal.class
  else:
    super_class = self.eval(frame, expr.obj_super_class).internal.class
  class.parent = super_class
  var ns = class.ns
  var scope = new_scope()
  var new_frame = FrameMgr.get(FrBody, ns, scope)
  new_frame.self = class
  for e in expr.obj_body:
    discard self.eval(new_frame, e)
  var instance = new_instance(class)
  result = new_gene_instance(instance)
  self.def_member(frame, name, result, true)
  discard self.call_method(frame, result, class, NEW_KEY, new_gene_gene())

EvaluatorMgr[ExMixin] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  self.def_member(frame, expr.mix_name, expr.mix, true)
  var ns = frame.ns
  var scope = new_scope()
  var new_frame = FrameMgr.get(FrBody, ns, scope)
  new_frame.self = expr.mix
  for e in expr.mix_body:
    discard self.eval(new_frame, e)
  result = expr.mix

EvaluatorMgr[ExInclude] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  # Copy methods to target class
  for e in expr.include_args:
    var mix = self.eval(frame, e)
    for name, meth in mix.internal.mix.methods:
      frame.self.internal.class.methods[name] = meth

EvaluatorMgr[ExNew] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var class = self.eval(frame, expr.new_class)
  var instance = new_instance(class.internal.class)
  result = new_gene_instance(instance)
  discard self.call_method(frame, result, class.internal.class, NEW_KEY, expr.new_args)

EvaluatorMgr[ExMethod] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var meth = expr.meth
  if expr.meth_fn_native != nil:
    meth.internal.meth.fn_native = self.eval(frame, expr.meth_fn_native).internal.native_meth
  case frame.self.internal.kind:
  of GeneClass:
    meth.internal.meth.class = frame.self.internal.class
    frame.self.internal.class.methods[meth.internal.meth.name.to_key] = meth.internal.meth
  of GeneMixin:
    frame.self.internal.mix.methods[meth.internal.meth.name.to_key] = meth.internal.meth
  else:
    not_allowed()
  result = meth

EvaluatorMgr[ExInvokeMethod] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var instance = self.eval(frame, expr.invoke_self)
  var class = instance.get_class
  result = self.call_method(frame, instance, class, expr.invoke_meth, expr.invoke_args)

EvaluatorMgr[ExSuper] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var instance = frame.self
  var meth = frame.scope[METHOD_OPTION_KEY].internal.meth
  var class = meth.class
  result = self.call_method(frame, instance, class.parent, meth.name.to_key, expr.super_args)

EvaluatorMgr[ExCall] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var target = self.eval(frame, expr.call_target)
  var call_self = GeneNil
  # if expr.call_props.has_key("self"):
  #   call_self = self.eval(frame, expr.call_props[SELF_KEY])
  var args: GeneValue
  if expr.call_args != nil:
    args = self.eval(frame, expr.call_args)
  else:
    args = new_gene_gene(GeneNil)
  var options = Table[FnOption, GeneValue]()
  result = self.call_fn(frame, call_self, target.internal.fn, args, options)

EvaluatorMgr[ExGetClass] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var val = self.eval(frame, expr.get_class_val)
  result = val.get_class

EvaluatorMgr[ExParse] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var s = self.eval(frame, expr.parse).str
  return new_gene_stream(read_all(s))

EvaluatorMgr[ExEval] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var old_self = frame.self
  try:
    if expr.eval_self != nil:
      frame.self = self.eval(frame, expr.eval_self)
    for e in expr.eval_args:
      var init_result = self.eval(frame, e)
      result = self.eval(frame, new_expr(expr, init_result))
  finally:
    frame.self = old_self

EvaluatorMgr[ExCallerEval] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var caller_frame = frame.parent
  for e in expr.caller_eval_args:
    result = self.eval(caller_frame, new_expr(expr, self.eval(frame, e)))
    if result.kind == GeneInternal and result.internal.kind == GeneExplode:
      for item in result.internal.explode.vec:
        result = self.eval(caller_frame, new_expr(expr, item))

EvaluatorMgr[ExMatch] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  result = self.match(frame, expr.match_pattern, self.eval(frame, expr.match_val), MatchDefault)

proc unquote(self: VirtualMachine, frame: Frame, expr: Expr, val: GeneValue): GeneValue {.inline.}
proc unquote(self: VirtualMachine, frame: Frame, expr: Expr, val: seq[GeneValue]): seq[GeneValue] =
  for item in val:
    var r = self.unquote(frame, expr, item)
    if item.kind == GeneGene and item.gene.type == Unquote and item.gene.props.get_or_default(DISCARD_KEY, false):
      discard
    else:
      result.add(r)

proc unquote(self: VirtualMachine, frame: Frame, expr: Expr, val: GeneValue): GeneValue =
  case val.kind:
  of GeneVector:
    result = new_gene_vec()
    result.vec = self.unquote(frame, expr, val.vec)
  of GeneMap:
    result = new_gene_map()
    for k, v in val.map:
      result.map[k]= self.unquote(frame, expr, v)
  of GeneGene:
    if val.gene.type == Unquote:
      var e = new_expr(expr, val.gene.data[0])
      result = self.eval(frame, e)
    else:
      result = new_gene_gene(self.unquote(frame, expr, val.gene.type))
      for k, v in val.gene.props:
        result.gene.props[k]= self.unquote(frame, expr, v)
      result.gene.data = self.unquote(frame, expr, val.gene.data)
  of GeneSet:
    todo()
  of GeneSymbol:
    return val
  of GeneComplexSymbol:
    return val
  else:
    return val

EvaluatorMgr[ExQuote] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var val = expr.quote_val
  result = self.unquote(frame, expr, val)

EvaluatorMgr[ExExit] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  if expr.exit == nil:
    quit()
  else:
    var code = self.eval(frame, expr.exit)
    quit(code.int)

EvaluatorMgr[ExEnv] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var env = self.eval(frame, expr.env)
  result = get_env(env.str)
  if result.str.len == 0:
    result = self.eval(frame, expr.env_default).to_s

EvaluatorMgr[ExPrint] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var print_to = stdout
  if expr.print_to != nil:
    print_to = self.eval(frame, expr.print_to).internal.file
  for e in expr.print:
    var v = self.eval(frame, e)
    case v.kind:
    of GeneString:
      print_to.write v.str
    else:
      print_to.write $v
  if expr.print_and_return:
    print_to.write "\n"

EvaluatorMgr[ExRoot] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  return self.eval(frame, expr.root)

EvaluatorMgr[ExLiteral] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  return expr.literal

EvaluatorMgr[ExString] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  return new_gene_string(expr.str)

EvaluatorMgr[ExComplexSymbol] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  return self.get_member(frame, expr.csymbol)

EvaluatorMgr[ExGene] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var target = self.eval(frame, expr.gene_type)
  case target.kind:
  of GeneInternal:
    case target.internal.kind:
    of GeneFunction:
      var options = Table[FnOption, GeneValue]()
      var args = self.eval_args(frame, expr.gene_props, expr.gene_data)
      result = self.call_fn(frame, GeneNil, target.internal.fn, args, options)
    of GeneMacro:
      result = self.call_macro(frame, GeneNil, target.internal.mac, expr)
    of GeneBlock:
      result = self.call_block(frame, GeneNil, target.internal.blk, expr)
    of GeneReturn:
      var val = GeneNil
      if expr.gene_data.len == 0:
        discard
      elif expr.gene_data.len == 1:
        val = self.eval(frame, expr.gene_data[0])
      else:
        not_allowed()
      raise Return(
        frame: target.internal.ret.frame,
        val: val,
      )
    of GeneAspect:
      result = self.call_aspect(frame, target.internal.aspect, expr)
    of GeneAspectInstance:
      var args = self.eval_args(frame, expr.gene_props, expr.gene_data)
      result = self.call_aspect_instance(frame, target.internal.aspect_instance, args)
    of GeneNativeFn:
      var args = self.eval_args(frame, expr.gene_props, expr.gene_data)
      result = target.internal.native_fn(args.gene.props, args.gene.data)
    of GeneSelector:
      var val = self.eval(frame, expr.gene_data[0])
      var selector = target.internal.selector
      try:
        result = selector.search(val)
      except SelectorNoResult:
        var default_expr: Expr
        for e in expr.gene_props:
          if e.map_key == DEFAULT_KEY:
            default_expr = e.map_val
            break
        if default_expr != nil:
          result = self.eval(frame, default_expr)
        else:
          raise

    # of GeneIteratorWrapper:
    #   var p = target.internal.iterator_wrapper
    #   var args = self.eval_args(frame, expr.gene_props, expr.gene_data)
    #   result = p(args.gene.data)
    else:
      todo($target.internal.kind)
  of GeneString:
    var str = target.str
    for item in expr.gene_data:
      str &= self.eval(frame, item).to_s
    result = new_gene_string_move(str)
  else:
    result = new_gene_gene(target)
    for e in expr.gene_props:
      result.gene.props[e.map_key] = self.eval(frame, e.map_val)
    for e in expr.gene_data:
      result.gene.data.add(self.eval(frame, e))

EvaluatorMgr[ExEnum] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var e = expr.enum
  self.def_member(frame, e.name, e, true)

EvaluatorMgr[ExFor] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  try:
    var for_in = self.eval(frame, expr.for_in)
    var first, second: GeneValue
    case expr.for_vars.kind:
    of GeneSymbol:
      first = expr.for_vars
    of GeneVector:
      first = expr.for_vars.vec[0]
      second = expr.for_vars.vec[1]
    else:
      not_allowed()

    if second == nil:
      var val = first.symbol.to_key
      frame.scope.def_member(val, GeneNil)
      case for_in.kind:
      of GeneRange:
        for i in for_in.range_start.int..<for_in.range_end.int:
          try:
            frame.scope[val] = i
            for e in expr.for_blk:
              discard self.eval(frame, e)
          except Continue:
            discard
      of GeneVector:
        for i in for_in.vec:
          try:
            frame.scope[val] = i
            for e in expr.for_blk:
              discard self.eval(frame, e)
          except Continue:
            discard
      # of GeneInternal:
      #   case for_in.internal.kind:
      #   of GeneIterator:
      #     for _, v in for_in.internal.iterator():
      #       try:
      #         frame.scope[val] = v
      #         for e in expr.for_blk:
      #           discard self.eval(frame, e)
      #       except Continue:
      #         discard
      #   else:
      #     todo($for_in.internal.kind)
      else:
        todo($for_in.kind)
    else:
      var key = first.symbol.to_key
      var val = second.symbol.to_key
      frame.scope.def_member(key, GeneNil)
      frame.scope.def_member(val, GeneNil)
      case for_in.kind:
      of GeneVector:
        for k, v in for_in.vec:
          try:
            frame.scope[key] = k
            frame.scope[val] = v
            for e in expr.for_blk:
              discard self.eval(frame, e)
          except Continue:
            discard
      of GeneMap:
        for k, v in for_in.map:
          try:
            frame.scope[key] = k.to_s
            frame.scope[val] = v
            for e in expr.for_blk:
              discard self.eval(frame, e)
          except Continue:
            discard
      else:
        todo()
  except Break:
    discard

EvaluatorMgr[ExParseCmdArgs] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var cmd_args = self.eval(frame, expr.cmd_args)
  var r = expr.cmd_args_schema.match(cmd_args.vec.map(proc(v: GeneValue): string = v.str))
  if r.kind == AmSuccess:
    for k, v in r.fields:
      var name = k
      if k.starts_with("--"):
        name = k[2..^1]
      elif k.starts_with("-"):
        name = k[1..^1]
      self.def_member(frame, name, v, false)
  else:
    todo()

EvaluatorMgr[ExRepl] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  return repl(self, frame, eval_only, true)

EvaluatorMgr[ExAsync] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  try:
    var val = self.eval(frame, expr.async)
    if val.kind == GeneInternal and val.internal.kind == GeneFuture:
      return val
    var future = new_future[GeneValue]()
    future.complete(val)
    result = future_to_gene(future)
  except CatchableError as e:
    var future = new_future[GeneValue]()
    future.fail(e)
    result = future_to_gene(future)

EvaluatorMgr[ExAsyncCallback] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  # Register callback to future
  var acb_self = self.eval(frame, expr.acb_self).internal.future
  var acb_callback = self.eval(frame, expr.acb_callback)
  if acb_self.finished:
    if expr.acb_success and not acb_self.failed:
      discard self.call_target(frame, acb_callback, @[acb_self.read()], expr)
    elif not expr.acb_success and acb_self.failed:
      # TODO: handle exceptions that are not CatchableError
      var ex = error_to_gene(cast[ref CatchableError](acb_self.read_error()))
      discard self.call_target(frame, acb_callback, @[ex], expr)
  else:
    acb_self.add_callback proc() {.gcsafe.} =
      if expr.acb_success and not acb_self.failed:
        discard self.call_target(frame, acb_callback, @[acb_self.read()], expr)
      elif not expr.acb_success and acb_self.failed:
        # TODO: handle exceptions that are not CatchableError
        var ex = error_to_gene(cast[ref CatchableError](acb_self.read_error()))
        discard self.call_target(frame, acb_callback, @[ex], expr)

EvaluatorMgr[ExSelector] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var selector = new_selector()
  if expr.parallel_mode:
    for item in expr.selector:
      var v = self.eval(frame, item)
      selector.children.add(gene_to_selector_item(v))
  else:
    var first = self.eval(frame, expr.selector[0])
    var selector_item = gene_to_selector_item(first)
    selector.children.add(selector_item)
    for i in 1..<expr.selector.len:
      var item = self.eval(frame, expr.selector[i])
      var new_selector_item = gene_to_selector_item(item)
      selector_item.children.add(new_selector_item)
      selector_item = new_selector_item
  result = selector

proc case_equals(input: GeneValue, pattern: GeneValue): bool =
  case input.kind:
  of GeneInt:
    case pattern.kind:
    of GeneInt:
      result = input.int == pattern.int
    of GeneRange:
      result = input.int >= pattern.range_start.int and input.int < pattern.range_end.int
    else:
      not_allowed($pattern.kind)
  else:
    result = input == pattern

EvaluatorMgr[ExCase] = proc(self: VirtualMachine, frame: Frame, expr: Expr): GeneValue =
  var input = self.eval(frame, expr.case_input)
  for pair in expr.case_more_mapping:
    var pattern = self.eval(frame, pair[0])
    if input.case_equals(pattern):
      return self.eval(frame, expr.case_blks[pair[1]])
  result = self.eval(frame, expr.case_else)

proc add_to_native*(name: string, fn: GeneValue) =
  var native = VM.gene_ns.internal.ns[NATIVE_KEY]
  if native.has_key(name.to_key):
    not_allowed()
  native.internal.ns[name.to_key] = fn

proc init_native*() =
  add_to_native "run_forever",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      run_forever()

  add_to_native "class_new",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var name = data[0].symbol_or_str
      result = new_class(name)
      result.internal.class.parent = data[1].internal.class

  add_to_native "file_open",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var file = open(data[0].str)
      result = file

  add_to_native "file_close",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      data[0].internal.file.close()

  add_to_native "file_read",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var file = data[0]
      case file.kind:
      of GeneString:
        result = read_file(file.str)
      else:
        var internal = data[0].internal
        if internal.kind == GeneFile:
          result = internal.file.read_all()

  add_to_native "file_read_async",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var file = data[0]
      case file.kind:
      of GeneString:
        var f = open_async(file.str)
        var future = f.read_all()
        var future2 = new_future[GeneValue]()
        future.add_callback proc() {.gcsafe.} =
          future2.complete(future.read())
        return future_to_gene(future2)
      else:
        todo()

  add_to_native "file_write",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var file = data[0]
      var content = data[1]
      write_file(file.str, content.str)

  add_to_native "os_exec",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var cmd = data[0].str
      # var cmd_data = data[1].vec.map(proc(v: GeneValue):string = v.to_s)
      var (output, _) = execCmdEx(cmd)
      result = output

  add_to_native "json_parse",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = data[0].str.parse_json

  add_to_native "csv_parse",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var parser = CsvParser()
      var sep = ','
      # Detect whether it's a tsv (Tab Separated Values)
      if data[0].str.contains('\t'):
        sep = '\t'
      parser.open(new_string_stream(data[0].str), "unknown.csv", sep)
      if not props.get_or_default("skip_headers".to_key, false):
        parser.read_header_row()
      result = new_gene_vec()
      while parser.read_row():
        var row: seq[GeneValue]
        row.add(parser.row.map(proc(s: string): GeneValue = new_gene_string(s)))
        result.vec.add(new_gene_vec(row))

  add_to_native "http_get",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var url = data[0].str
      var headers = newHttpHeaders()
      for k, v in data[2].map:
        headers.add(k.to_s, v.str)
      var client = newHttpClient()
      client.headers = headers
      result = client.get_content(url)

  add_to_native "http_get_async",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var url = data[0].str
      var headers = newHttpHeaders()
      for k, v in data[2].map:
        headers.add(k.to_s, v.str)
      var client = newAsyncHttpClient()
      client.headers = headers
      var f = client.get_content(url)
      var future = new_future[GeneValue]()
      f.add_callback proc() {.gcsafe.} =
        future.complete(f.read())
      result = future_to_gene(future)

  add_to_native "http_req_url",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var req = cast[ptr Request](self.any)[]
      result = $req.url

  add_to_native "http_req_method",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var req = cast[ptr Request](self.any)[]
      result = $req.req_method

  add_to_native "http_req_params",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = new_gene_map()
      var req = cast[ptr Request](self.any)[]
      var parts = req.url.query.split('&')
      for p in parts:
        if p == "":
          continue
        var pair = p.split('=', 2)
        result.map[pair[0].to_key] = pair[1]

  add_to_native "http_start_server",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var port: int
      if data[0].kind == GeneString:
        port = data[0].str.parse_int
      else:
        port = data[0].int
      proc handler(req: Request) {.async gcsafe.} =
        try:
          var args = new_gene_gene(GeneNil)
          args.gene.data.add(new_gene_any(req.unsafe_addr, HTTP_REQUEST_KEY))
          var body = VM.call_fn(GeneNil, data[1].internal.fn, args).str
          await req.respond(Http200, body, new_http_headers())
        except CatchableError as e:
          discard req.respond(Http500, e.msg, new_http_headers())
      var server = new_async_http_server()
      async_check server.serve(Port(port), handler)

  add_to_native "base64",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = encode(data[0].str)

  add_to_native "url_encode",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = encode_url(data[0].str)

  add_to_native "url_decode",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = decode_url(data[0].str)

  add_to_native "sleep",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      sleep(data[0].int)

  add_to_native "sleep_async",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var f = sleep_async(data[0].int)
      var future = new_future[GeneValue]()
      f.add_callback proc() {.gcsafe.} =
        future.complete(GeneNil)
      result = future_to_gene(future)

  add_to_native "date_today",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var date = now()
      result = new_gene_date(date.year, cast[int](date.month), date.monthday)

  add_to_native "time_now",
    proc(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var date = now()
      result = new_gene_datetime(date)

  add_to_native "object_is",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.is_a(data[0].internal.class)

  add_to_native "object_to_s",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.to_s()

  add_to_native "object_to_json",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.to_json()

  # add_to_native "object_to_xml",
  #   proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
  #     result = self.to_xml()

  add_to_native "ns_name",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      if self.kind == GeneInternal and self.internal.kind == GeneNamespace:
        result = self.internal.ns.name
      else:
        not_allowed($self & " is not a Namespace.")

  add_to_native "class_name",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      if self.kind == GeneInternal and self.internal.kind == GeneClass:
        result = self.internal.class.name
      else:
        not_allowed($self & " is not a class.")

  add_to_native "class_parent",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      if self.kind == GeneInternal and self.internal.kind == GeneClass:
        result = self.internal.class.parent
      else:
        not_allowed($self & " is not a class.")

  add_to_native "exception_message",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var ex = self.internal.exception
      result = ex.msg

  add_to_native "future_finished",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.internal.future.finished

  add_to_native "package_name",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.internal.pkg.name

  add_to_native "package_version",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.internal.pkg.version

  add_to_native "str_size",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.str.len

  add_to_native "str_append",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self
      for i in 0..<data.len:
        self.str.add(data[i].to_s)

  add_to_native "str_substr",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      case data.len:
      of 1:
        var start = data[0].int
        if start >= 0:
          return self.str[start..^1]
        else:
          return self.str[^(-start)..^1]
      of 2:
        var start = data[0].int
        var end_index = data[1].int
        if start >= 0:
          if end_index >= 0:
            return self.str[start..end_index]
          else:
            return self.str[start..^(-end_index)]
        else:
          if end_index >= 0:
            return self.str[^(-start)..end_index]
          else:
            return self.str[^(-start)..^(-end_index)]
      else:
        not_allowed("substr expects 1 or 2 arguments")

  add_to_native "str_split",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var separator = data[0].str
      case data.len:
      of 1:
        var parts = self.str.split(separator)
        result = new_gene_vec()
        for part in parts:
          result.vec.add(part)
      of 2:
        var maxsplit = data[1].int - 1
        var parts = self.str.split(separator, maxsplit)
        result = new_gene_vec()
        for part in parts:
          result.vec.add(part)
      else:
        not_allowed("split expects 1 or 2 arguments")

  add_to_native "str_contains",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var substr = data[0].str
      result = self.str.find(substr) >= 0

  add_to_native "str_index",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var substr = data[0].str
      result = self.str.find(substr)

  add_to_native "str_rindex",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var substr = data[0].str
      result = self.str.rfind(substr)

  add_to_native "str_char_at",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var i = data[0].int
      result = self.str[i]

  add_to_native "str_to_i",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.str.parse_int

  add_to_native "str_trim",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.str.strip

  add_to_native "str_starts_with",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var substr = data[0].str
      result = self.str.startsWith(substr)

  add_to_native "str_ends_with",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var substr = data[0].str
      result = self.str.endsWith(substr)

  add_to_native "str_to_upper_case",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.str.toUpper

  add_to_native "str_to_lower_case",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.str.toLower

  add_to_native "date_year",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.date.year

  add_to_native "datetime_sub",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var duration = self.date.toTime() - data[0].date.toTime()
      result = duration.inMicroseconds / 1000_000

  add_to_native "datetime_elapsed",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var duration = now().toTime() - self.date.toTime()
      result = duration.inMicroseconds / 1000_000

  add_to_native "time_hour",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.time.hour

  add_to_native "array_size",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.vec.len

  add_to_native "array_get",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.vec[data[0].int]

  add_to_native "array_set",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      self.vec[data[0].int] = data[1]
      result = data[1]

  add_to_native "array_add",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      self.vec.add(data[0])
      result = self

  add_to_native "array_del",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var index = data[0].int
      result = self.vec[index]
      self.vec.delete(index)

  add_to_native "map_size",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.map.len

  add_to_native "map_contain",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var s = data[0].str
      result = self.map.has_key(s.to_key)

  add_to_native "map_merge",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self
      for k, v in data[0].map:
        self.map[k] = v

  add_to_native "gene_type",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.gene.type

  add_to_native "gene_props",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.gene.props

  add_to_native "gene_contain",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      var s = data[0].str
      result = self.gene.props.has_key(s.to_key)

  add_to_native "gene_data",
    proc(self: GeneValue, props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
      result = self.gene.data

  # add_to_native "props_iterator",
  #   to_gene proc(args: varargs[GeneValue]): iterator(): tuple[k, v: GeneValue] =
  #     var self = args[0]
  #     result = iterator(): tuple[k, v: GeneValue] =
  #       case self.kind:
  #       of GeneGene:
  #         for k, v in self.gene.props:
  #           yield (k.to_s.str_to_gene, v)
  #       of GeneMap:
  #         for k, v in self.map:
  #           yield (k.to_s.str_to_gene, v)
  #       else:
  #         not_allowed()

when isMainModule:
  import os, times

  if commandLineParams().len == 0:
    echo "\nUsage: interpreter <GENE FILE>\n"
    quit(0)

  init_app_and_vm()
  var module = new_module()
  var frame = FrameMgr.get(FrModule, module.root_ns, new_scope())
  let e = VM.prepare(readFile(commandLineParams()[0]))
  let start = cpuTime()
  let result = VM.eval(frame, e)
  echo "Time: " & $(cpuTime() - start)
  echo result

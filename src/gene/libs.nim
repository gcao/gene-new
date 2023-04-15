import os, osproc, random, base64, tables, sequtils, strutils, times, parsecsv, streams, nre
import asyncdispatch, asyncfile

import ./types
import ./json
import ./interpreter_base

proc object_class(self: Value, args: Value): Value =
  Value(kind: VkClass, class: self.get_class())

proc object_is(self: Value, args: Value): Value =
  self.is_a(args.gene_children[0].class)

proc object_to_json(self: Value, args: Value): Value =
  self.to_json()

proc object_to_s(self: Value, args: Value): Value =
  self.to_s

proc object_to_bool(self: Value, args: Value): Value =
  self.to_bool

proc on_member_missing(self: Value, args: Value): Value =
  case self.kind
  of VkNamespace:
    self.ns.on_member_missing.add(args.gene_children[0])
  of VkClass:
    self.class.ns.on_member_missing.add(args.gene_children[0])
  of VkMixin:
    self.mixin.ns.on_member_missing.add(args.gene_children[0])
  else:
    todo("member_missing " & $self.kind)

proc to_function(node: Value): Function =
  var first = node.gene_children[0]
  var name = first.str

  var matcher = new_arg_matcher()
  matcher.parse(node.gene_children[1])

  var body: seq[Value] = @[]
  for i in 2..<node.gene_children.len:
    body.add node.gene_children[i]

  body = wrap_with_try(body)
  result = new_fn(name, matcher, body)
  result.async = node.gene_props.get_or_default("async", false)

proc class_fn(self: Value, args: Value): Value =
  # define a fn like method on a class
  var fn = to_function(args)

  var m = Method(
    name: fn.name,
    callable: Value(kind: VkFunction, fn: fn),
  )
  m.callable.fn.ns = self.class.ns
  case self.kind:
  of VkClass:
    m.class = self.class
    self.class.methods[m.name] = m
  of VkMixin:
    self.mixin.methods[m.name] = m
  else:
    not_allowed()

proc macro_invoker*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var scope = new_scope()
  scope.set_parent(target.macro.parent_scope, target.macro.parent_scope_max)
  var new_frame = Frame(ns: target.macro.ns, scope: scope)
  new_frame.parent = frame

  var args = cast[ExLiteral](expr).data
  var match_result = self.match(new_frame, target.macro.matcher, args)
  case match_result.kind:
  of MatchSuccess:
    discard
  of MatchMissingFields:
    for field in match_result.missing:
      not_allowed("Argument " & field.to_s & " is missing.")
  else:
    todo()

  if target.macro.body_compiled == nil:
    target.macro.body_compiled = translate(target.macro.body)

  try:
    result = self.eval(new_frame, target.macro.body_compiled)
  except Return as r:
    result = r.val
  except system.Exception as e:
    if self.repl_on_error:
      result = repl_on_error(self, frame, e)
      discard
    else:
      raise

proc arg_translator(value: Value): Expr {.gcsafe.} =
  var expr = new_ex_literal(value)
  expr.evaluator = macro_invoker
  result = expr

proc to_macro(node: Value): Macro =
  var first = node.gene_children[0]
  var name: string
  if first.kind == VkSymbol:
    name = first.str
  elif first.kind == VkComplexSymbol:
    name = first.csymbol[^1]

  var matcher = new_arg_matcher()
  matcher.parse(node.gene_children[1])

  var body: seq[Value] = @[]
  for i in 2..<node.gene_children.len:
    body.add node.gene_children[i]

  body = wrap_with_try(body)
  result = new_macro(name, matcher, body)
  result.translator = arg_translator

proc class_macro(self: Value, args: Value): Value =
  # define a macro like method on a class
  var mac = to_macro(args)

  var m = Method(
    name: mac.name,
    callable: Value(kind: VkMacro, `macro`: mac),
  )
  m.callable.macro.ns = self.class.ns
  case self.kind:
  of VkClass:
    m.class = self.class
    self.class.methods[m.name] = m
  of VkMixin:
    self.mixin.methods[m.name] = m
  else:
    not_allowed()

proc exception_message(self: Value, args: Value): Value =
  self.exception.msg

proc exception_stack(self: Value, args: Value): Value =
  self.exception.get_stack_trace()

proc exception_to_s(self: Value, args: Value): Value =
  self.exception.msg & "\n" & self.exception.get_stack_trace()

proc string_size(self: Value, args: Value): Value =
  self.str.len

proc string_to_i(self: Value, args: Value): Value =
  self.str.parse_int

proc string_append(self: Value, args: Value): Value =
  result = self
  for item in args.gene_children:
    if not item.is_nil:
      self.str.add(item.to_s)

proc string_substr(self: Value, args: Value): Value =
  case args.gene_children.len:
  of 1:
    var start = args.gene_children[0].int
    if start >= 0:
      return self.str[start..^1]
    else:
      return self.str[^(-start)..^1]
  of 2:
    var start = args.gene_children[0].int
    var end_index = args.gene_children[1].int
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

proc string_split(self: Value, args: Value): Value =
  var separator = args.gene_children[0].str
  case args.gene_children.len:
  of 1:
    var parts = self.str.split(separator)
    result = new_gene_vec()
    for part in parts:
      result.vec.add(part)
  of 2:
    var maxsplit = args.gene_children[1].int - 1
    var parts = self.str.split(separator, maxsplit)
    result = new_gene_vec()
    for part in parts:
      result.vec.add(part)
  else:
    not_allowed("split expects 1 or 2 arguments")

proc string_contains(self: Value, args: Value): Value =
  var substr = args.gene_children[0].str
  result = self.str.find(substr) >= 0

proc string_index(self: Value, args: Value): Value =
  var substr = args.gene_children[0].str
  result = self.str.find(substr)

proc string_rindex(self: Value, args: Value): Value =
  var substr = args.gene_children[0].str
  result = self.str.rfind(substr)

proc string_char_at(self: Value, args: Value): Value =
  var i = args.gene_children[0].int
  result = self.str[i]

proc string_trim(self: Value, args: Value): Value =
  result = self.str.strip

proc string_starts_with(self: Value, args: Value): Value =
  var substr = args.gene_children[0].str
  result = self.str.startsWith(substr)

proc string_ends_with(self: Value, args: Value): Value =
  var substr = args.gene_children[0].str
  result = self.str.endsWith(substr)

proc string_to_uppercase(self: Value, args: Value): Value =
  result = self.str.toUpper

proc string_to_lowercase(self: Value, args: Value): Value =
  result = self.str.toLower

proc array_size(self: Value, args: Value): Value =
  result = self.vec.len

proc array_add(self: Value, args: Value): Value =
  self.vec.add(args.gene_children[0])
  result = self

proc array_del(self: Value, args: Value): Value =
  var index = args.gene_children[0].int
  result = self.vec[index]
  self.vec.delete(index)

proc array_empty(self: Value, args: Value): Value =
  result = self.vec.len == 0

proc array_contains(self: Value, args: Value): Value =
  result = self.vec.contains(args.gene_children[0])

proc map_size(self: Value, args: Value): Value =
  result = self.map.len

proc map_keys(self: Value, args: Value): Value =
  result = new_gene_vec()
  for k, _ in self.map:
    result.vec.add(k.to_s)

proc map_values(self: Value, args: Value): Value =
  result = new_gene_vec()
  for _, v in self.map:
    result.vec.add(v)

proc gene_type(self: Value, args: Value): Value =
  self.gene_type

proc gene_props(self: Value, args: Value): Value =
  result = new_gene_map()
  for k, v in self.gene_props:
    result.map[k] = v

proc gene_children(self: Value, args: Value): Value =
  result = new_gene_vec()
  for item in self.gene_children:
    result.vec.add(item)

proc os_exec(args: Value): Value =
  var cmd = args.gene_children[0].str
  var (output, _) = execCmdEx(cmd)
  result = output

proc file_read(args: Value): Value =
  var file = args.gene_children[0]
  case file.kind:
  of VkString:
    result = read_file(file.str)
  of VkFile:
    result = file.file_content
  else:
    todo($file.kind)

proc file_read(self: Value, args: Value): Value =
  self.native_file.read_all()

proc file_read_async(args: Value): Value =
  var file = args.gene_children[0]
  case file.kind:
  of VkString:
    var f = open_async(file.str)
    var future = f.read_all()
    var future2 = new_future[Value]()
    future.add_callback proc() {.gcsafe.} =
      future2.complete(future.read())
    return new_gene_future(future2)
  else:
    todo($file.kind)

proc file_write(args: Value): Value =
  var file = args.gene_children[0]
  var content = args.gene_children[1]
  write_file(file.str, content.str)

proc json_parse(args: Value): Value =
  result = args.gene_children[0].str.parse_json

proc csv_parse(args: Value): Value =
  var parser = CsvParser()
  var sep = ','
  # Detect whether it's a tsv (Tab Separated Values)
  if args.gene_children[0].str.contains('\t'):
    sep = '\t'
  parser.open(new_string_stream(args.gene_children[0].str), "unknown.csv", sep)
  if not args.gene_props.get_or_default("skip_headers", false):
    parser.read_header_row()
  result = new_gene_vec()
  while parser.read_row():
    var row: seq[Value]
    row.add(parser.row.map(proc(s: string): Value = new_gene_string(s)))
    result.vec.add(new_gene_vec(row))

proc today(args: Value): Value =
  var date = now()
  result = new_gene_date(date.year, cast[int](date.month), date.monthday)

proc now(args: Value): Value =
  var date = now()
  result = new_gene_datetime(date)

proc date_year(self: Value, args: Value): Value =
  result = self.date.year

proc time_elapsed(self: Value, args: Value): Value =
  var duration = now().toTime() - self.date.toTime()
  result = duration.inMicroseconds / 1000_000

proc time_hour(self: Value, args: Value): Value =
  result = self.time.hour

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    self.gene_ns.ns["todo"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_todo".} =
      todo(args.gene_children[0].to_s)
    self.global_ns.ns["todo"] = self.gene_ns.ns["todo"]
    self.gene_ns.ns["not_allowed"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_not_allowed".} =
      not_allowed(args.gene_children[0].to_s)
    self.global_ns.ns["not_allowed"] = self.gene_ns.ns["not_allowed"]


    self.gene_ns.ns["rand"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_rand".} =
      if args.gene_children.len == 0:
        return new_gene_float(rand(1.0))
      else:
        return rand(args.gene_children[0].int)

    self.gene_ns.ns["sleep"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_sleep".} =
      var time = 1
      if args.gene_children.len >= 1:
        time = args.gene_children[0].int
      sleep(time)
      # sleep will trigger async event check
      for i in 1..ASYNC_WAIT_LIMIT:
        discard VM.eval(nil, NOOP_EXPR)

    self.gene_ns.ns["sleep_async"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_sleep_async".} =
      var f = sleep_async(args.gene_children[0].int)
      var future = new_future[Value]()
      f.add_callback proc() {.gcsafe.} =
        future.complete(Value(kind: VkNil))
      result = new_gene_future(future)

    self.gene_ns.ns["base64"] = new_gene_native_fn proc(args: Value): Value =
      encode(args.gene_children[0].str)
    self.gene_ns.ns["base64_decode"] = new_gene_native_fn proc(args: Value): Value =
      case args.gene_children[0].kind:
      of VkString:
        return decode(args.gene_children[0].str)
      of VkNil:
        return ""
      else:
        todo("base64_decode " & $args.gene_children[0].kind)
    self.gene_ns.ns["run_forever"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_run_forever".} =
      run_forever()

    self.object_class.def_native_method("class", object_class)
    self.object_class.def_native_method("is", object_is)
    self.object_class.def_native_method("to_s", object_to_s)
    self.object_class.def_native_method("to_json", object_to_json)
    self.object_class.def_native_method("to_bool", object_to_bool)
    self.object_class.def_native_method "call", proc(self: Value, args: Value): Value {.name:"object_call".} =
      todo("Object.call")
    self.gene_ns.ns["Object"] = self.object_class
    self.global_ns.ns["Object"] = self.object_class

    self.class_class = Value(kind: VkClass, class: new_class("Class"))
    self.class_class.class.parent = self.object_class.class
    self.class_class.def_native_method "name", proc(self: Value, args: Value): Value =
      self.class.name
    self.class_class.def_native_method "parent", proc(self: Value, args: Value): Value =
      Value(kind: VkClass, class: self.class.parent)
    self.class_class.def_native_method "fn", class_fn
    self.class_class.def_native_macro_method "macro", class_macro
    self.class_class.def_native_method "members", proc(self: Value, args: Value): Value {.name:"class_members".} =
      self.class.ns.get_members()
    self.class_class.def_native_method "member_names", proc(self: Value, args: Value): Value {.name:"class_member_names".} =
      self.class.ns.member_names()
    self.class_class.def_native_method "has_member", proc(self: Value, args: Value): Value {.name:"class_has_member".} =
      self.class.ns.members.has_key(args[0].to_s)
    self.class_class.def_native_method "on_member_missing", on_member_missing
    self.class_class.def_native_method "on_extended", proc(self: Value, args: Value): Value {.name:"class_on_extended" } =
      self.class.on_extended = args.gene_children[0]

    self.gene_ns.ns["Class"] = self.class_class
    self.global_ns.ns["Class"] = self.class_class

    self.mixin_class = Value(kind: VkClass, class: new_class("Mixin"))
    self.mixin_class.class.parent = self.object_class.class
    self.mixin_class.def_native_method "name", proc(self: Value, args: Value): Value {.name:"mixin_name".} =
      self.mixin.name
    self.mixin_class.def_native_method "members", proc(self: Value, args: Value): Value {.name:"mixin_members".} =
      self.mixin.ns.get_members()
    self.mixin_class.def_native_method "member_names", proc(self: Value, args: Value): Value {.name:"mixin_member_names".} =
      self.mixin.ns.member_names()
    self.mixin_class.def_native_method "has_member", proc(self: Value, args: Value): Value {.name:"mixin_has_member".} =
      self.mixin.ns.members.has_key(args[0].to_s)
    self.mixin_class.def_native_method "on_member_missing", on_member_missing
    self.mixin_class.def_native_method "on_included", proc(self: Value, args: Value): Value {.name:"mixin_on_extended" } =
      self.class.on_extended = args.gene_children[0]
    self.gene_ns.ns["Mixin"] = self.mixin_class
    self.global_ns.ns["Mixin"] = self.mixin_class

    self.exception_class = Value(kind: VkClass, class: new_class("Exception"))
    self.exception_class.class.parent = self.object_class.class
    self.exception_class.def_native_method("message", exception_message)
    self.exception_class.def_native_method("stacktrace", exception_stack)
    self.exception_class.def_native_method("to_s", exception_to_s)
    self.gene_ns.ns["Exception"] = self.exception_class
    self.global_ns.ns["Exception"] = self.exception_class

    self.module_class = Value(kind: VkClass, class: new_class("Module"))
    self.module_class.class.parent = self.object_class.class
    self.module_class.def_native_method "name", proc(self: Value, args: Value): Value =
      self.module.name
    self.module_class.def_native_method "set_name", proc(self: Value, args: Value): Value =
      self.module.name = args.gene_children[0].str

    self.namespace_class = Value(kind: VkClass, class: new_class("Namespace"))
    self.namespace_class.class.parent = self.object_class.class
    self.namespace_class.def_native_method "name", proc(self: Value, args: Value): Value {.name:"ns_name".} =
      self.ns.name
    self.namespace_class.def_native_method "members", proc(self: Value, args: Value): Value {.name:"ns_members".} =
      self.ns.get_members()
    self.namespace_class.def_native_method "member_names", proc(self: Value, args: Value): Value {.name:"ns_member_names".} =
      self.ns.member_names()
    self.namespace_class.def_native_method "has_member", proc(self: Value, args: Value): Value {.name:"ns_has_member".} =
      self.ns.members.has_key(args[0].to_s)
    self.namespace_class.def_native_method "on_member_missing", on_member_missing
    self.gene_ns.ns["Namespace"] = self.namespace_class
    self.global_ns.ns["Namespace"] = self.namespace_class

    self.bool_class = Value(kind: VkClass, class: new_class("Bool"))
    self.bool_class.class.parent = self.object_class.class
    self.gene_ns.ns["Bool"] = self.bool_class
    self.global_ns.ns["Bool"] = self.bool_class

    self.int_class = Value(kind: VkClass, class: new_class("Int"))
    self.int_class.class.parent = self.object_class.class
    self.gene_ns.ns["Int"] = self.int_class
    self.global_ns.ns["Int"] = self.int_class

    self.nil_class = Value(kind: VkClass, class: new_class("Nil"))
    self.nil_class.class.parent = self.object_class.class
    self.gene_ns.ns["Nil"] = self.nil_class
    self.global_ns.ns["Nil"] = self.nil_class

    self.string_class = Value(kind: VkClass, class: new_class("String"))
    self.string_class.class.parent = self.object_class.class
    self.gene_ns.ns["String"] = self.string_class
    self.global_ns.ns["String"] = self.string_class
    self.string_class.def_native_method("size", string_size)
    self.string_class.def_native_method("to_i", string_to_i)
    self.string_class.def_native_method("append", string_append)
    self.string_class.def_native_method("substr", string_substr)
    self.string_class.def_native_method("split", string_split)
    self.string_class.def_native_method("contains", string_contains)
    self.string_class.def_native_method("index", string_index)
    self.string_class.def_native_method("rindex", string_rindex)
    self.string_class.def_native_method("char_at", string_char_at)
    self.string_class.def_native_method("trim", string_trim)
    self.string_class.def_native_method("starts_with", string_starts_with)
    self.string_class.def_native_method("ends_with", string_ends_with)
    self.string_class.def_native_method("to_uppercase", string_to_uppercase)
    self.string_class.def_native_method("to_lowercase", string_to_lowercase)
    self.string_class.def_native_method "replace", proc(self: Value, args: Value): Value {.name:"string_replace".} =
      var first = args.gene_children[0]
      var second = args.gene_children[1]
      case first.kind:
      of VkString:
        return self.str.replace(first.str, second.str)
      of VkRegex:
        return self.str.replace(first.regex, second.str)
      else:
        todo("string_replace " & $first.kind)

    self.symbol_class = Value(kind: VkClass, class: new_class("Symbol"))
    self.symbol_class.class.parent = self.object_class.class
    self.gene_ns.ns["Symbol"] = self.symbol_class
    self.global_ns.ns["Symbol"] = self.symbol_class

    self.complex_symbol_class = Value(kind: VkClass, class: new_class("ComplexSymbol"))
    self.complex_symbol_class.class.parent = self.object_class.class
    self.complex_symbol_class.def_native_method "parts", proc(self: Value, args: Value): Value {.name:"complex_symbol_parts".} =
      result = new_gene_vec()
      for item in self.csymbol:
        result.vec.add(item)
    self.gene_ns.ns["ComplexSymbol"] = self.complex_symbol_class
    self.global_ns.ns["ComplexSymbol"] = self.complex_symbol_class

    self.array_class = Value(kind: VkClass, class: new_class("Array"))
    self.array_class.class.parent = self.object_class.class
    self.array_class.def_native_method("size", array_size)
    self.array_class.def_native_method("add", array_add)
    self.array_class.def_native_method("del", array_del)
    self.array_class.def_native_method("empty", array_empty)
    self.array_class.def_native_method("contains", array_contains)
    self.gene_ns.ns["Array"] = self.array_class
    self.global_ns.ns["Array"] = self.array_class

    self.map_class = Value(kind: VkClass, class: new_class("Map"))
    self.map_class.class.parent = self.object_class.class
    self.map_class.def_native_method("size", map_size)
    self.map_class.def_native_method("keys", map_keys)
    self.map_class.def_native_method("values", map_values)
    self.map_class.def_native_method "contains", proc(self: Value, args: Value): Value {.name:"map_contains".} =
      self.map.has_key(args.gene_children[0].str)
    self.gene_ns.ns["Map"] = self.map_class
    self.global_ns.ns["Map"] = self.map_class

    self.gene_class = Value(kind: VkClass, class: new_class("Gene"))
    self.gene_class.class.parent = self.object_class.class
    self.gene_class.def_native_method("type", gene_type)
    self.gene_class.def_native_method("props", gene_props)
    self.gene_class.def_native_method("children", gene_children)
    self.gene_class.def_native_method "contains", proc(self: Value, args: Value): Value {.name:"gene_contains".} =
      var s = args.gene_children[0].str
      result = self.gene_props.has_key(s)
    self.gene_ns.ns["Gene"] = self.gene_class
    self.global_ns.ns["Gene"] = self.gene_class

    self.function_class = Value(kind: VkClass, class: new_class("Function"))
    self.function_class.class.parent = self.object_class.class
    self.function_class.def_native_method "call", proc(self: Value, args: Value): Value {.name:"function_call".} =
      VM.call(new_frame(), self, args)

    self.file_class = Value(kind: VkClass, class: new_class("File"))
    self.file_class.class.parent = self.object_class.class
    self.file_class.class.ns["read"] = Value(kind: VkNativeFn, native_fn: file_read)
    self.file_class.class.ns["read_async"] = Value(kind: VkNativeFn, native_fn: file_read_async)
    self.file_class.class.ns["write"] = Value(kind: VkNativeFn, native_fn: file_write)
    self.file_class.def_native_method("read", file_read)
    self.gene_ns.ns["File"] = self.file_class

    var os_ns = new_namespace("os")
    os_ns["exec"] = Value(kind: VkNativeFn, native_fn: os_exec)
    self.gene_ns.ns["os"] = Value(kind: VkNamespace, ns: os_ns)

    var json_ns = new_namespace("json")
    json_ns["parse"] = Value(kind: VkNativeFn, native_fn: json_parse)
    self.gene_ns.ns["json"] = Value(kind: VkNamespace, ns: json_ns)

    var csv_ns = new_namespace("csv")
    csv_ns["parse"] = Value(kind: VkNativeFn, native_fn: csv_parse)
    self.gene_ns.ns["csv"] = Value(kind: VkNamespace, ns: csv_ns)

    self.date_class = Value(kind: VkClass, class: new_class("Date"))
    self.date_class.class.parent = self.object_class.class
    self.date_class.def_native_method("year", date_year)

    self.datetime_class = Value(kind: VkClass, class: new_class("DateTime"))
    self.datetime_class.class.parent = self.date_class.class
    self.datetime_class.def_native_method("elapsed", time_elapsed)

    self.time_class = Value(kind: VkClass, class: new_class("Time"))
    self.time_class.class.parent = self.object_class.class
    self.time_class.def_native_method("hour", time_hour)

    self.selector_class = Value(kind: VkClass, class: new_class("Selector"))
    self.selector_class.class.parent = self.object_class.class
    # self.selector_class.ns["descendants"] = ...

    self.package_class = Value(kind: VkClass, class: new_class("Package"))
    self.package_class.class.parent = self.object_class.class
    self.package_class.def_native_method "name", proc(self: Value, args: Value): Value {.name:"package_name".} =
      self.pkg.name
    self.gene_ns.ns["Package"] = self.package_class

    self.gene_ns.ns["today"] = Value(kind: VkNativeFn, native_fn: today)
    self.gene_ns.ns["now"] = Value(kind: VkNativeFn, native_fn: now)

    discard self.eval(self.runtime.pkg, """
    ($with gene/String
      (method lines _
        (self .split "\n")
      )
    )

    ($with gene/Array
      (method each block
        (for item in self
          (block item)
        )
      )

      (method map block
        (var result [])
        (for item in self
          (result .add (block item))
        )
        result
      )

      (method find block
        (for item in self
          (if (block item)
            (return item)
          )
        )
      )

      (method select block
        (var result [])
        (for item in self
          (if (block item) (result .add item))
        )
        result
      )

      (method join [with = ""]
        (var s "")
        (for [i item] in self
          (s .append item/.to_s (if (i < (/.size - 1)) with))
        )
        s
      )
    )

    ($with gene/Map
      (method map block
        (var result [])
        (for [k v] in self
          (result .add (block k v))
        )
        result
      )
    )

    (global/genex .on_member_missing
      (fnx name
        (case name
        when "http"
          (import from name ^^native)
          /http
        when "sqlite"
          (import from name ^^native)
          /sqlite
        when "mysql"
          (import from name ^^native)
          /mysql
        )
      )
    )

    (ns genex/html
      (class Tag
        (method init [name attrs = {} children = []]
          (/name     = name)
          (/attrs    = attrs)
          (/children = children)
        )

        (method to_s _
          ("<" /name
            ((/attrs .map
              ([k v] ->
                (if (v == false)
                  ""
                elif (v == true)
                  k
                else
                  (" " k "=\""
                    (if (k == "style")
                      ((v .map ([name value] -> ("" name ":" value ";"))).join)
                    else
                      v/.to_s
                    )
                    "\""
                  )
                )
              )
            ).join)
            ">"
            (if (/children/.size > 0)
              ("\n"
                ((/children .join "\n").trim)
              "\n")
            )
            "</" /name ">"
          )
        )
      )

      # TODO: leaf tags
      (ns tags
        # HTML, BODY, DIV etc are part of this namespace
        (var tags :[
          HTML HEAD META LINK TITLE STYLE SCRIPT BODY
          DIV P SPAN
          BR
          HEADER H1
          IMG
          FORM LABEL INPUT BUTTON
          UL LI
          SVG RECT LINE
        ])
        (for tag in tags
          (tag = (tag .to_s))
          (eval
            ($render :(fn %tag [^attrs... children...]
              (new Tag %tag attrs children)
            ))
          )
        )
      )

      (fn style [^props...]
        (fnx node
          (if (node .contains "style")
            (node/style .merge props)
          else
            ($set node @style props)
          )
          (:void)
        )
      )
    )

    (ns genex/test
      (class TestFailure < gene/Exception
      )
      (fn fail [message = "Test failed."]
        (throw TestFailure message)
      )
      (macro check [expr message = ("Check " expr " failed.")]
        (if not ($caller_eval expr)
          (fail message)
        )
      )
    )
    """)

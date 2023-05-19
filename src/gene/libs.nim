import os, osproc, random, base64, tables, sequtils, strutils, times, parsecsv, streams, nre
import asyncdispatch, asyncfile

import ./types
import ./json
import ./interpreter_base

proc object_class(frame: Frame, self: Value, args: Value): Value =
  Value(kind: VkClass, class: self.get_class())

proc object_is(frame: Frame, self: Value, args: Value): Value =
  self.is_a(args.gene_children[0].class)

proc object_to_json(frame: Frame, self: Value, args: Value): Value =
  self.to_json()

proc object_to_s(frame: Frame, self: Value, args: Value): Value =
  self.to_s

proc object_to_bool(frame: Frame, self: Value, args: Value): Value =
  self.to_bool

proc on_member_missing(frame: Frame, self: Value, args: Value): Value =
  case self.kind
  of VkNamespace:
    self.ns.on_member_missing.add(args.gene_children[0])
  of VkClass:
    self.class.ns.on_member_missing.add(args.gene_children[0])
  of VkMixin:
    self.mixin.ns.on_member_missing.add(args.gene_children[0])
  else:
    todo("member_missing " & $self.kind)

proc to_ctor(node: Value): Function =
  var name = "ctor"

  var matcher = new_arg_matcher()
  matcher.parse(node.gene_children[0])

  var body: seq[Value] = @[]
  for i in 1..<node.gene_children.len:
    body.add node.gene_children[i]

  body = wrap_with_try(body)
  result = new_fn(name, matcher, body)

proc class_ctor(frame: Frame, self: Value, args: Value): Value =
  var fn = to_ctor(args)
  fn.ns = frame.ns
  self.class.constructor = Value(kind: VkFunction, fn: fn)

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

proc class_fn(frame: Frame, self: Value, args: Value): Value =
  # define a fn like method on a class
  var fn = to_function(args)

  var m = Method(
    name: fn.name,
    callable: Value(kind: VkFunction, fn: fn),
  )
  case self.kind:
  of VkClass:
    m.class = self.class
    fn.ns = self.class.ns
    self.class.methods[m.name] = m
  of VkMixin:
    fn.ns = self.mixin.ns
    self.mixin.methods[m.name] = m
  else:
    not_allowed()

proc class_method(frame: Frame, self: Value, args: Value): Value =
  var m = Method(
    name: args.gene_children[0].str,
    callable: args.gene_children[1],
  )
  case self.kind:
  of VkClass:
    m.class = self.class
    self.class.methods[m.name] = m
  of VkMixin:
    self.mixin.methods[m.name] = m
  else:
    not_allowed()

proc macro_invoker*(frame: Frame, expr: var Expr): Value =
  var target = frame.callable
  var scope = new_scope()
  scope.set_parent(target.macro.parent_scope, target.macro.parent_scope_max)
  var new_frame = Frame(ns: target.macro.ns, scope: scope)
  new_frame.parent = frame

  var args = cast[ExLiteral](expr).data
  var match_result = match(new_frame, target.macro.matcher, args)
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
    result = eval(new_frame, target.macro.body_compiled)
  except Return as r:
    result = r.val
  except system.Exception as e:
    if VM.repl_on_error:
      result = repl_on_error(frame, e)
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

proc class_macro(frame: Frame, self: Value, args: Value): Value =
  # define a macro like method on a class
  var mac = to_macro(args)

  var m = Method(
    name: mac.name,
    callable: Value(kind: VkMacro, `macro`: mac),
  )
  case self.kind:
  of VkClass:
    m.class = self.class
    mac.ns = self.class.ns
    self.class.methods[m.name] = m
  of VkMixin:
    mac.ns = self.mixin.ns
    self.mixin.methods[m.name] = m
  else:
    not_allowed()

proc exception_message(frame: Frame, self: Value, args: Value): Value =
  self.exception.msg

proc exception_stack(frame: Frame, self: Value, args: Value): Value =
  self.exception.get_stack_trace()

proc exception_to_s(frame: Frame, self: Value, args: Value): Value =
  self.exception.msg & "\n" & self.exception.get_stack_trace()

proc string_size(frame: Frame, self: Value, args: Value): Value =
  self.str.len

proc string_to_i(frame: Frame, self: Value, args: Value): Value =
  self.str.parse_int

proc string_append(frame: Frame, self: Value, args: Value): Value =
  result = self
  for item in args.gene_children:
    if not item.is_nil:
      self.str.add(item.to_s)

proc string_substr(frame: Frame, self: Value, args: Value): Value =
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

proc string_split(frame: Frame, self: Value, args: Value): Value =
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

proc string_contains(frame: Frame, self: Value, args: Value): Value =
  var substr = args.gene_children[0].str
  result = self.str.find(substr) >= 0

proc string_index(frame: Frame, self: Value, args: Value): Value =
  var substr = args.gene_children[0].str
  result = self.str.find(substr)

proc string_rindex(frame: Frame, self: Value, args: Value): Value =
  var substr = args.gene_children[0].str
  result = self.str.rfind(substr)

proc string_char_at(frame: Frame, self: Value, args: Value): Value =
  var i = args.gene_children[0].int
  result = self.str[i]

proc string_trim(frame: Frame, self: Value, args: Value): Value =
  result = self.str.strip

proc string_starts_with(frame: Frame, self: Value, args: Value): Value =
  var substr = args.gene_children[0].str
  result = self.str.startsWith(substr)

proc string_ends_with(frame: Frame, self: Value, args: Value): Value =
  var substr = args.gene_children[0].str
  result = self.str.endsWith(substr)

proc string_to_uppercase(frame: Frame, self: Value, args: Value): Value =
  result = self.str.toUpper

proc string_to_lowercase(frame: Frame, self: Value, args: Value): Value =
  result = self.str.toLower

proc array_size(frame: Frame, self: Value, args: Value): Value =
  result = self.vec.len

proc array_add(frame: Frame, self: Value, args: Value): Value =
  self.vec.add(args.gene_children[0])
  result = self

proc array_del(frame: Frame, self: Value, args: Value): Value =
  var index = args.gene_children[0].int
  result = self.vec[index]
  self.vec.delete(index)

proc array_empty(frame: Frame, self: Value, args: Value): Value =
  result = self.vec.len == 0

proc array_contains(frame: Frame, self: Value, args: Value): Value =
  result = self.vec.contains(args.gene_children[0])

proc map_size(frame: Frame, self: Value, args: Value): Value =
  result = self.map.len

proc map_keys(frame: Frame, self: Value, args: Value): Value =
  result = new_gene_vec()
  for k, _ in self.map:
    result.vec.add(k.to_s)

proc map_values(frame: Frame, self: Value, args: Value): Value =
  result = new_gene_vec()
  for _, v in self.map:
    result.vec.add(v)

proc gene_type(frame: Frame, self: Value, args: Value): Value =
  self.gene_type

proc gene_props(frame: Frame, self: Value, args: Value): Value =
  result = new_gene_map()
  for k, v in self.gene_props:
    result.map[k] = v

proc gene_children(frame: Frame, self: Value, args: Value): Value =
  result = new_gene_vec()
  for item in self.gene_children:
    result.vec.add(item)

proc os_exec(frame: Frame, args: Value): Value =
  var cmd = args.gene_children[0].str
  var (output, _) = execCmdEx(cmd)
  result = output

proc file_read(frame: Frame, args: Value): Value =
  var file = args.gene_children[0]
  case file.kind:
  of VkString:
    result = read_file(file.str)
  of VkFile:
    result = file.file_content
  else:
    todo($file.kind)

proc file_read(frame: Frame, self: Value, args: Value): Value =
  self.native_file.read_all()

proc file_read_async(frame: Frame, args: Value): Value =
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

proc file_write(frame: Frame, args: Value): Value =
  var file = args.gene_children[0]
  var content = args.gene_children[1]
  write_file(file.str, content.str)

proc json_parse(frame: Frame, args: Value): Value =
  result = args.gene_children[0].str.parse_json

proc csv_parse(frame: Frame, args: Value): Value =
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

proc today(frame: Frame, args: Value): Value =
  var date = now()
  result = new_gene_date(date.year, cast[int](date.month), date.monthday)

proc now(frame: Frame, args: Value): Value =
  var date = now()
  result = new_gene_datetime(date)

proc date_year(frame: Frame, self: Value, args: Value): Value =
  result = self.date.year

proc time_elapsed(frame: Frame, self: Value, args: Value): Value =
  var duration = now().toTime() - self.date.toTime()
  result = duration.inMicroseconds / 1000_000

proc time_hour(frame: Frame, self: Value, args: Value): Value =
  result = self.time.hour

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_ns.ns["todo"] = new_gene_native_fn proc(frame: Frame, args: Value): Value {.name:"gene_todo".} =
      todo(args.gene_children[0].to_s)
    VM.global_ns.ns["todo"] = VM.gene_ns.ns["todo"]
    VM.gene_ns.ns["not_allowed"] = new_gene_native_fn proc(frame: Frame, args: Value): Value {.name:"gene_not_allowed".} =
      not_allowed(args.gene_children[0].to_s)
    VM.global_ns.ns["not_allowed"] = VM.gene_ns.ns["not_allowed"]


    VM.gene_ns.ns["rand"] = new_gene_native_fn proc(frame: Frame, args: Value): Value {.name:"gene_rand".} =
      if args.gene_children.len == 0:
        return new_gene_float(rand(1.0))
      else:
        return rand(args.gene_children[0].int)

    VM.gene_ns.ns["sleep"] = new_gene_native_fn proc(frame: Frame, args: Value): Value {.name:"gene_sleep".} =
      var time = 1
      if args.gene_children.len >= 1:
        time = args.gene_children[0].int
      sleep(time)
      check_async_ops_and_channel()

    VM.gene_ns.ns["sleep_async"] = new_gene_native_fn proc(frame: Frame, args: Value): Value {.name:"gene_sleep_async".} =
      var f = sleep_async(args.gene_children[0].int)
      var future = new_future[Value]()
      f.add_callback proc() {.gcsafe.} =
        future.complete(Value(kind: VkNil))
      result = new_gene_future(future)

    VM.gene_ns.ns["base64"] = new_gene_native_fn proc(frame: Frame, args: Value): Value =
      encode(args.gene_children[0].str)
    VM.gene_ns.ns["base64_decode"] = new_gene_native_fn proc(frame: Frame, args: Value): Value =
      case args.gene_children[0].kind:
      of VkString:
        return decode(args.gene_children[0].str)
      of VkNil:
        return ""
      else:
        todo("base64_decode " & $args.gene_children[0].kind)
    VM.gene_ns.ns["run_forever"] = new_gene_native_fn proc(frame: Frame, args: Value): Value {.name:"gene_run_forever".} =
      run_forever()

    VM.object_class.def_native_method("class", object_class)
    VM.object_class.def_native_method("is", object_is)
    VM.object_class.def_native_method("to_s", object_to_s)
    VM.object_class.def_native_method("to_json", object_to_json)
    VM.object_class.def_native_method("to_bool", object_to_bool)
    VM.object_class.def_native_method "call", proc(frame: Frame, self: Value, args: Value): Value {.name:"object_call".} =
      todo("Object.call")
    VM.gene_ns.ns["Object"] = VM.object_class
    VM.global_ns.ns["Object"] = VM.object_class

    VM.class_class = Value(kind: VkClass, class: new_class("Class"))
    VM.class_class.class.parent = VM.object_class.class
    VM.class_class.def_native_method "name", proc(frame: Frame, self: Value, args: Value): Value =
      self.class.name
    VM.class_class.def_native_method "parent", proc(frame: Frame, self: Value, args: Value): Value =
      Value(kind: VkClass, class: self.class.parent)
    VM.class_class.def_native_macro_method "ctor", class_ctor
    VM.class_class.def_native_macro_method "fn", class_fn
    VM.class_class.def_native_macro_method "macro", class_macro
    VM.class_class.def_native_method "method", class_method
    VM.class_class.def_native_method "members", proc(frame: Frame, self: Value, args: Value): Value {.name:"class_members".} =
      self.class.ns.get_members()
    VM.class_class.def_native_method "member_names", proc(frame: Frame, self: Value, args: Value): Value {.name:"class_member_names".} =
      self.class.ns.member_names()
    VM.class_class.def_native_method "has_member", proc(frame: Frame, self: Value, args: Value): Value {.name:"class_has_member".} =
      self.class.ns.members.has_key(args[0].to_s)
    VM.class_class.def_native_method "on_member_missing", on_member_missing
    VM.class_class.def_native_method "on_extended", proc(frame: Frame, self: Value, args: Value): Value {.name:"class_on_extended" } =
      self.class.on_extended = args.gene_children[0]

    VM.gene_ns.ns["Class"] = VM.class_class
    VM.global_ns.ns["Class"] = VM.class_class

    VM.mixin_class = Value(kind: VkClass, class: new_class("Mixin"))
    VM.mixin_class.class.parent = VM.object_class.class
    VM.mixin_class.def_native_method "name", proc(frame: Frame, self: Value, args: Value): Value {.name:"mixin_name".} =
      self.mixin.name
    VM.mixin_class.def_native_macro_method "fn", class_fn
    VM.mixin_class.def_native_macro_method "macro", class_macro
    VM.mixin_class.def_native_method "method", class_method
    VM.mixin_class.def_native_method "members", proc(frame: Frame, self: Value, args: Value): Value {.name:"mixin_members".} =
      self.mixin.ns.get_members()
    VM.mixin_class.def_native_method "member_names", proc(frame: Frame, self: Value, args: Value): Value {.name:"mixin_member_names".} =
      self.mixin.ns.member_names()
    VM.mixin_class.def_native_method "has_member", proc(frame: Frame, self: Value, args: Value): Value {.name:"mixin_has_member".} =
      self.mixin.ns.members.has_key(args[0].to_s)
    VM.mixin_class.def_native_method "on_member_missing", on_member_missing
    VM.mixin_class.def_native_method "on_included", proc(frame: Frame, self: Value, args: Value): Value {.name:"mixin_on_extended" } =
      self.class.on_extended = args.gene_children[0]
    VM.gene_ns.ns["Mixin"] = VM.mixin_class
    VM.global_ns.ns["Mixin"] = VM.mixin_class

    VM.exception_class = Value(kind: VkClass, class: new_class("Exception"))
    VM.exception_class.class.parent = VM.object_class.class
    VM.exception_class.def_native_method("message", exception_message)
    VM.exception_class.def_native_method("stacktrace", exception_stack)
    VM.exception_class.def_native_method("to_s", exception_to_s)
    VM.gene_ns.ns["Exception"] = VM.exception_class
    VM.global_ns.ns["Exception"] = VM.exception_class

    VM.module_class = Value(kind: VkClass, class: new_class("Module"))
    VM.module_class.class.parent = VM.object_class.class
    VM.module_class.def_native_method "name", proc(frame: Frame, self: Value, args: Value): Value =
      self.module.name
    VM.module_class.def_native_method "set_name", proc(frame: Frame, self: Value, args: Value): Value =
      self.module.name = args.gene_children[0].str

    VM.namespace_class = Value(kind: VkClass, class: new_class("Namespace"))
    VM.namespace_class.class.parent = VM.object_class.class
    VM.namespace_class.def_native_method "name", proc(frame: Frame, self: Value, args: Value): Value {.name:"ns_name".} =
      self.ns.name
    VM.namespace_class.def_native_method "members", proc(frame: Frame, self: Value, args: Value): Value {.name:"ns_members".} =
      self.ns.get_members()
    VM.namespace_class.def_native_method "member_names", proc(frame: Frame, self: Value, args: Value): Value {.name:"ns_member_names".} =
      self.ns.member_names()
    VM.namespace_class.def_native_method "has_member", proc(frame: Frame, self: Value, args: Value): Value {.name:"ns_has_member".} =
      self.ns.members.has_key(args[0].to_s)
    VM.namespace_class.def_native_method "on_member_missing", on_member_missing
    VM.gene_ns.ns["Namespace"] = VM.namespace_class
    VM.global_ns.ns["Namespace"] = VM.namespace_class

    VM.bool_class = Value(kind: VkClass, class: new_class("Bool"))
    VM.bool_class.class.parent = VM.object_class.class
    VM.gene_ns.ns["Bool"] = VM.bool_class
    VM.global_ns.ns["Bool"] = VM.bool_class

    VM.int_class = Value(kind: VkClass, class: new_class("Int"))
    VM.int_class.class.parent = VM.object_class.class
    VM.gene_ns.ns["Int"] = VM.int_class
    VM.global_ns.ns["Int"] = VM.int_class

    VM.nil_class = Value(kind: VkClass, class: new_class("Nil"))
    VM.nil_class.class.parent = VM.object_class.class
    VM.gene_ns.ns["Nil"] = VM.nil_class
    VM.global_ns.ns["Nil"] = VM.nil_class

    VM.string_class = Value(kind: VkClass, class: new_class("String"))
    VM.string_class.class.parent = VM.object_class.class
    VM.gene_ns.ns["String"] = VM.string_class
    VM.global_ns.ns["String"] = VM.string_class
    VM.string_class.def_native_method("size", string_size)
    VM.string_class.def_native_method("to_i", string_to_i)
    VM.string_class.def_native_method("append", string_append)
    VM.string_class.def_native_method("substr", string_substr)
    VM.string_class.def_native_method("split", string_split)
    VM.string_class.def_native_method("contains", string_contains)
    VM.string_class.def_native_method("index", string_index)
    VM.string_class.def_native_method("rindex", string_rindex)
    VM.string_class.def_native_method("char_at", string_char_at)
    VM.string_class.def_native_method("trim", string_trim)
    VM.string_class.def_native_method("starts_with", string_starts_with)
    VM.string_class.def_native_method("ends_with", string_ends_with)
    VM.string_class.def_native_method("to_uppercase", string_to_uppercase)
    VM.string_class.def_native_method("to_lowercase", string_to_lowercase)
    VM.string_class.def_native_method "replace", proc(frame: Frame, self: Value, args: Value): Value {.name:"string_replace".} =
      var first = args.gene_children[0]
      var second = args.gene_children[1]
      case first.kind:
      of VkString:
        return self.str.replace(first.str, second.str)
      of VkRegex:
        return self.str.replace(first.regex, second.str)
      else:
        todo("string_replace " & $first.kind)

    VM.symbol_class = Value(kind: VkClass, class: new_class("Symbol"))
    VM.symbol_class.class.parent = VM.object_class.class
    VM.gene_ns.ns["Symbol"] = VM.symbol_class
    VM.global_ns.ns["Symbol"] = VM.symbol_class

    VM.complex_symbol_class = Value(kind: VkClass, class: new_class("ComplexSymbol"))
    VM.complex_symbol_class.class.parent = VM.object_class.class
    VM.complex_symbol_class.def_native_method "parts", proc(frame: Frame, self: Value, args: Value): Value {.name:"complex_symbol_parts".} =
      result = new_gene_vec()
      for item in self.csymbol:
        result.vec.add(item)
    VM.gene_ns.ns["ComplexSymbol"] = VM.complex_symbol_class
    VM.global_ns.ns["ComplexSymbol"] = VM.complex_symbol_class

    VM.array_class = Value(kind: VkClass, class: new_class("Array"))
    VM.array_class.class.parent = VM.object_class.class
    VM.array_class.def_native_method("size", array_size)
    VM.array_class.def_native_method("add", array_add)
    VM.array_class.def_native_method("del", array_del)
    VM.array_class.def_native_method("empty", array_empty)
    VM.array_class.def_native_method("contains", array_contains)
    VM.gene_ns.ns["Array"] = VM.array_class
    VM.global_ns.ns["Array"] = VM.array_class

    VM.map_class = Value(kind: VkClass, class: new_class("Map"))
    VM.map_class.class.parent = VM.object_class.class
    VM.map_class.def_native_method("size", map_size)
    VM.map_class.def_native_method("keys", map_keys)
    VM.map_class.def_native_method("values", map_values)
    VM.map_class.def_native_method "contains", proc(frame: Frame, self: Value, args: Value): Value {.name:"map_contains".} =
      self.map.has_key(args.gene_children[0].str)
    VM.gene_ns.ns["Map"] = VM.map_class
    VM.global_ns.ns["Map"] = VM.map_class

    VM.gene_class = Value(kind: VkClass, class: new_class("Gene"))
    VM.gene_class.class.parent = VM.object_class.class
    VM.gene_class.def_native_method("type", gene_type)
    VM.gene_class.def_native_method("props", gene_props)
    VM.gene_class.def_native_method("children", gene_children)
    VM.gene_class.def_native_method "contains", proc(frame: Frame, self: Value, args: Value): Value {.name:"gene_contains".} =
      var s = args.gene_children[0].str
      result = self.gene_props.has_key(s)
    VM.gene_ns.ns["Gene"] = VM.gene_class
    VM.global_ns.ns["Gene"] = VM.gene_class

    VM.function_class = Value(kind: VkClass, class: new_class("Function"))
    VM.function_class.class.parent = VM.object_class.class
    VM.function_class.def_native_method "call", proc(frame: Frame, self: Value, args: Value): Value {.name:"function_call".} =
      call(new_frame(), self, args)

    VM.file_class = Value(kind: VkClass, class: new_class("File"))
    VM.file_class.class.parent = VM.object_class.class
    VM.file_class.class.ns["read"] = Value(kind: VkNativeFn, native_fn: file_read)
    VM.file_class.class.ns["read_async"] = Value(kind: VkNativeFn, native_fn: file_read_async)
    VM.file_class.class.ns["write"] = Value(kind: VkNativeFn, native_fn: file_write)
    VM.file_class.def_native_method("read", file_read)
    VM.gene_ns.ns["File"] = VM.file_class

    var os_ns = new_namespace("os")
    os_ns["exec"] = Value(kind: VkNativeFn, native_fn: os_exec)
    VM.gene_ns.ns["os"] = Value(kind: VkNamespace, ns: os_ns)

    var json_ns = new_namespace("json")
    json_ns["parse"] = Value(kind: VkNativeFn, native_fn: json_parse)
    VM.gene_ns.ns["json"] = Value(kind: VkNamespace, ns: json_ns)

    var csv_ns = new_namespace("csv")
    csv_ns["parse"] = Value(kind: VkNativeFn, native_fn: csv_parse)
    VM.gene_ns.ns["csv"] = Value(kind: VkNamespace, ns: csv_ns)

    VM.date_class = Value(kind: VkClass, class: new_class("Date"))
    VM.date_class.class.parent = VM.object_class.class
    VM.date_class.def_native_method("year", date_year)

    VM.datetime_class = Value(kind: VkClass, class: new_class("DateTime"))
    VM.datetime_class.class.parent = VM.date_class.class
    VM.datetime_class.def_native_method("elapsed", time_elapsed)

    VM.time_class = Value(kind: VkClass, class: new_class("Time"))
    VM.time_class.class.parent = VM.object_class.class
    VM.time_class.def_native_method("hour", time_hour)

    VM.selector_class = Value(kind: VkClass, class: new_class("Selector"))
    VM.selector_class.class.parent = VM.object_class.class
    # VM.selector_class.ns["descendants"] = ...

    VM.package_class = Value(kind: VkClass, class: new_class("Package"))
    VM.package_class.class.parent = VM.object_class.class
    VM.package_class.def_native_method "name", proc(frame: Frame, self: Value, args: Value): Value {.name:"package_name".} =
      self.pkg.name
    VM.gene_ns.ns["Package"] = VM.package_class

    VM.gene_ns.ns["today"] = Value(kind: VkNativeFn, native_fn: today)
    VM.gene_ns.ns["now"] = Value(kind: VkNativeFn, native_fn: now)

    discard eval(VM.runtime.pkg, """
    ($with gene/String
      (.fn lines _
        (self .split "\n")
      )
    )

    ($with gene/Array
      (.fn each block
        (for item in self
          (block item)
        )
      )

      (.fn map block
        (var result [])
        (for item in self
          (result .add (block item))
        )
        result
      )

      (.fn find block
        (for item in self
          (if (block item)
            (return item)
          )
        )
      )

      (.fn select block
        (var result [])
        (for item in self
          (if (block item) (result .add item))
        )
        result
      )

      (.fn join [with = ""]
        (var s "")
        (for [i item] in self
          (s .append item/.to_s (if (i < (/.size - 1)) with))
        )
        s
      )
    )

    ($with gene/Map
      (.fn map block
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
        (.ctor [name attrs = {} children = []]
          (/name     = name)
          (/attrs    = attrs)
          (/children = children)
        )

        (.fn to_s _
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

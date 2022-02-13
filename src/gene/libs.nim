import os, osproc, random, base64, tables, sequtils, strutils, times, parsecsv, streams, nre
import asyncdispatch, asyncfile

import ./types
import ./json
import ./map_key
import ./exprs
import ./interpreter_base
import ./features/oop

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
  else:
    todo($file.kind)

proc file_read(self: Value, args: Value): Value =
  self.file.read_all()

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
  if not args.gene_props.get_or_default("skip_headers".to_key, false):
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

proc add_success_callback(self: Value, args: Value): Value =
  # Register callback to future
  if self.future.finished:
    if not self.future.failed:
      var callback_args = new_gene_gene()
      callback_args.gene_children.add(self.future.read())
      var frame = Frame()
      discard VM.call(frame, args.gene_children[0], callback_args)
  else:
    self.future.add_callback proc() {.gcsafe.} =
      if not self.future.failed:
        var callback_args = new_gene_gene()
        callback_args.gene_children.add(self.future.read())
        var frame = Frame()
        discard VM.call(frame, args.gene_children[0], callback_args)

proc add_failure_callback(self: Value, args: Value): Value =
  # Register callback to future
  if self.future.finished:
    if self.future.failed:
      var callback_args = new_gene_gene()
      var ex = error_to_gene(cast[ref system.Exception](self.future.read_error()))
      callback_args.gene_children.add(ex)
      var frame = Frame()
      discard VM.call(frame, args.gene_children[0], callback_args)
  else:
    self.future.add_callback proc() {.gcsafe.} =
      if self.future.failed:
        var callback_args = new_gene_gene()
        var ex = error_to_gene(cast[ref system.Exception](self.future.read_error()))
        callback_args.gene_children.add(ex)
        var frame = Frame()
        discard VM.call(frame, args.gene_children[0], callback_args)

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    GENE_NS.ns["todo"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_todo".} =
      todo(args.gene_children[0].to_s)
    GLOBAL_NS.ns["todo"] = GENE_NS.ns["todo"]
    GENE_NS.ns["not_allowed"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_not_allowed".} =
      not_allowed(args.gene_children[0].to_s)
    GLOBAL_NS.ns["not_allowed"] = GENE_NS.ns["not_allowed"]


    GENE_NS.ns["rand"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_rand".} =
      if args.gene_children.len == 0:
        return new_gene_float(rand(1.0))
      else:
        return rand(args.gene_children[0].int)

    GENE_NS.ns["sleep"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_sleep".} =
      sleep(args.gene_children[0].int)
    GENE_NS.ns["sleep_async"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_sleep_async".} =
      var f = sleep_async(args.gene_children[0].int)
      var future = new_future[Value]()
      f.add_callback proc() {.gcsafe.} =
        future.complete(Nil)
      result = new_gene_future(future)
    GENE_NS.ns["base64"] = new_gene_native_fn proc(args: Value): Value =
      encode(args.gene_children[0].str)
    GENE_NS.ns["base64_decode"] = new_gene_native_fn proc(args: Value): Value =
      case args.gene_children[0].kind:
      of VkString:
        return decode(args.gene_children[0].str)
      of VkNil:
        return ""
      else:
        todo("base64_decode " & $args.gene_children[0].kind)
    GENE_NS.ns["run_forever"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_run_forever".} =
      run_forever()

    ObjectClass = Value(kind: VkClass, class: new_class("Object"))
    ObjectClass.def_native_method("class", object_class)
    ObjectClass.def_native_method("is", object_is)
    ObjectClass.def_native_method("to_s", object_to_s)
    ObjectClass.def_native_method("to_json", object_to_json)
    ObjectClass.def_native_method("to_bool", object_to_bool)
    ObjectClass.def_native_method "call", proc(self: Value, args: Value): Value {.name:"object_call".} =
      todo("Object.call")
    GENE_NS.ns["Object"] = ObjectClass
    GLOBAL_NS.ns["Object"] = ObjectClass

    ClassClass = Value(kind: VkClass, class: new_class("Class"))
    ClassClass.class.parent = ObjectClass.class
    ClassClass.def_native_method "name", proc(self: Value, args: Value): Value =
      self.class.name
    ClassClass.def_native_method "parent", proc(self: Value, args: Value): Value =
      Value(kind: VkClass, class: self.class.parent)
    ClassClass.def_native_method "members", proc(self: Value, args: Value): Value {.name:"class_members".} =
      self.class.ns.get_members()
    ClassClass.def_native_method "member_names", proc(self: Value, args: Value): Value {.name:"class_member_names".} =
      self.class.ns.member_names()
    ClassClass.def_native_method "has_member", proc(self: Value, args: Value): Value {.name:"class_has_member".} =
      self.class.ns.members.has_key(args[0].to_s.to_key)
    ClassClass.def_native_method "on_member_missing", on_member_missing
    ClassClass.def_native_method "on_extended", proc(self: Value, args: Value): Value {.name:"class_on_extended" } =
      self.class.on_extended = args.gene_children[0]

    GENE_NS.ns["Class"] = ClassClass
    GLOBAL_NS.ns["Class"] = ClassClass

    MixinClass = Value(kind: VkClass, class: new_class("Mixin"))
    MixinClass.class.parent = ObjectClass.class
    MixinClass.def_native_method "name", proc(self: Value, args: Value): Value {.name:"mixin_name".} =
      self.mixin.name
    MixinClass.def_native_method "members", proc(self: Value, args: Value): Value {.name:"mixin_members".} =
      self.mixin.ns.get_members()
    MixinClass.def_native_method "member_names", proc(self: Value, args: Value): Value {.name:"mixin_member_names".} =
      self.mixin.ns.member_names()
    MixinClass.def_native_method "has_member", proc(self: Value, args: Value): Value {.name:"mixin_has_member".} =
      self.mixin.ns.members.has_key(args[0].to_s.to_key)
    MixinClass.def_native_method "on_member_missing", on_member_missing
    MixinClass.def_native_method "on_included", proc(self: Value, args: Value): Value {.name:"mixin_on_extended" } =
      self.class.on_extended = args.gene_children[0]
    GENE_NS.ns["Mixin"] = MixinClass
    GLOBAL_NS.ns["Mixin"] = MixinClass

    ExceptionClass = Value(kind: VkClass, class: new_class("Exception"))
    ExceptionClass.class.parent = ObjectClass.class
    ExceptionClass.def_native_method("message", exception_message)
    ExceptionClass.def_native_method("stacktrace", exception_stack)
    ExceptionClass.def_native_method("to_s", exception_to_s)
    GENE_NS.ns["Exception"] = ExceptionClass
    GLOBAL_NS.ns["Exception"] = ExceptionClass

    NamespaceClass = Value(kind: VkClass, class: new_class("Namespace"))
    NamespaceClass.class.parent = ObjectClass.class
    NamespaceClass.def_native_method "name", proc(self: Value, args: Value): Value {.name:"ns_name".} =
      self.ns.name
    NamespaceClass.def_native_method "members", proc(self: Value, args: Value): Value {.name:"ns_members".} =
      self.ns.get_members()
    NamespaceClass.def_native_method "member_names", proc(self: Value, args: Value): Value {.name:"ns_member_names".} =
      self.ns.member_names()
    NamespaceClass.def_native_method "has_member", proc(self: Value, args: Value): Value {.name:"ns_has_member".} =
      self.ns.members.has_key(args[0].to_s.to_key)
    NamespaceClass.def_native_method "on_member_missing", on_member_missing
    GENE_NS.ns["Namespace"] = NamespaceClass
    GLOBAL_NS.ns["Namespace"] = NamespaceClass

    BoolClass = Value(kind: VkClass, class: new_class("Bool"))
    BoolClass.class.parent = ObjectClass.class
    GENE_NS.ns["Bool"] = BoolClass
    GLOBAL_NS.ns["Bool"] = BoolClass

    IntClass = Value(kind: VkClass, class: new_class("Int"))
    IntClass.class.parent = ObjectClass.class
    GENE_NS.ns["Int"] = IntClass
    GLOBAL_NS.ns["Int"] = IntClass

    NilClass = Value(kind: VkClass, class: new_class("Nil"))
    NilClass.class.parent = ObjectClass.class
    GENE_NS.ns["Nil"] = NilClass
    GLOBAL_NS.ns["Nil"] = NilClass

    FutureClass = Value(kind: VkClass, class: new_class("Future"))
    FutureClass.class.parent = ObjectClass.class
    FutureClass.def_native_method("on_success", add_success_callback)
    FutureClass.def_native_method("on_failure", add_failure_callback)
    FutureClass.class.parent = ObjectClass.class
    GENE_NS.ns["Future"] = FutureClass

    StringClass = Value(kind: VkClass, class: new_class("String"))
    StringClass.class.parent = ObjectClass.class
    GENE_NS.ns["String"] = StringClass
    GLOBAL_NS.ns["String"] = StringClass
    StringClass.def_native_method("size", string_size)
    StringClass.def_native_method("to_i", string_to_i)
    StringClass.def_native_method("append", string_append)
    StringClass.def_native_method("substr", string_substr)
    StringClass.def_native_method("split", string_split)
    StringClass.def_native_method("contains", string_contains)
    StringClass.def_native_method("index", string_index)
    StringClass.def_native_method("rindex", string_rindex)
    StringClass.def_native_method("char_at", string_char_at)
    StringClass.def_native_method("trim", string_trim)
    StringClass.def_native_method("starts_with", string_starts_with)
    StringClass.def_native_method("ends_with", string_ends_with)
    StringClass.def_native_method("to_uppercase", string_to_uppercase)
    StringClass.def_native_method("to_lowercase", string_to_lowercase)
    StringClass.def_native_method "replace", proc(self: Value, args: Value): Value {.name:"string_replace".} =
      var first = args.gene_children[0]
      var second = args.gene_children[1]
      case first.kind:
      of VkString:
        return self.str.replace(first.str, second.str)
      of VkRegex:
        return self.str.replace(first.regex, second.str)
      else:
        todo("string_replace " & $first.kind)

    SymbolClass = Value(kind: VkClass, class: new_class("Symbol"))
    SymbolClass.class.parent = ObjectClass.class
    GENE_NS.ns["Symbol"] = SymbolClass
    GLOBAL_NS.ns["Symbol"] = SymbolClass

    ComplexSymbolClass = Value(kind: VkClass, class: new_class("ComplexSymbol"))
    ComplexSymbolClass.class.parent = ObjectClass.class
    ComplexSymbolClass.def_native_method "parts", proc(self: Value, args: Value): Value {.name:"complex_symbol_parts".} =
      result = new_gene_vec()
      for item in self.csymbol:
        result.vec.add(item)
    GENE_NS.ns["ComplexSymbol"] = ComplexSymbolClass
    GLOBAL_NS.ns["ComplexSymbol"] = ComplexSymbolClass

    ArrayClass = Value(kind: VkClass, class: new_class("Array"))
    ArrayClass.class.parent = ObjectClass.class
    ArrayClass.def_native_method("size", array_size)
    ArrayClass.def_native_method("add", array_add)
    ArrayClass.def_native_method("del", array_del)
    ArrayClass.def_native_method("empty", array_empty)
    ArrayClass.def_native_method("contains", array_contains)
    GENE_NS.ns["Array"] = ArrayClass
    GLOBAL_NS.ns["Array"] = ArrayClass

    MapClass = Value(kind: VkClass, class: new_class("Map"))
    MapClass.class.parent = ObjectClass.class
    MapClass.def_native_method("size", map_size)
    MapClass.def_native_method("keys", map_keys)
    MapClass.def_native_method("values", map_values)
    MapClass.def_native_method "contains", proc(self: Value, args: Value): Value {.name:"map_contains".} =
      self.map.has_key(args.gene_children[0].str.to_key)
    GENE_NS.ns["Map"] = MapClass
    GLOBAL_NS.ns["Map"] = MapClass

    GeneClass = Value(kind: VkClass, class: new_class("Gene"))
    GeneClass.class.parent = ObjectClass.class
    GeneClass.def_native_method("type", gene_type)
    GeneClass.def_native_method("props", gene_props)
    GeneClass.def_native_method("children", gene_children)
    GeneClass.def_native_method "contains", proc(self: Value, args: Value): Value {.name:"gene_contains".} =
      var s = args.gene_children[0].str
      result = self.gene_props.has_key(s.to_key)

    GENE_NS.ns["Gene"] = GeneClass
    GLOBAL_NS.ns["Gene"] = GeneClass

    FileClass = Value(kind: VkClass, class: new_class("File"))
    FileClass.class.parent = ObjectClass.class
    FileClass.class.ns["read"] = Value(kind: VkNativeFn, native_fn: file_read)
    FileClass.class.ns["read_async"] = Value(kind: VkNativeFn, native_fn: file_read_async)
    FileClass.class.ns["write"] = Value(kind: VkNativeFn, native_fn: file_write)
    FileClass.def_native_method("read", file_read)
    GENE_NS.ns["File"] = FileClass

    var os_ns = new_namespace("os")
    os_ns["exec"] = Value(kind: VkNativeFn, native_fn: os_exec)
    GENE_NS.ns["os"] = Value(kind: VkNamespace, ns: os_ns)

    var json_ns = new_namespace("json")
    json_ns["parse"] = Value(kind: VkNativeFn, native_fn: json_parse)
    GENE_NS.ns["json"] = Value(kind: VkNamespace, ns: json_ns)

    var csv_ns = new_namespace("csv")
    csv_ns["parse"] = Value(kind: VkNativeFn, native_fn: csv_parse)
    GENE_NS.ns["csv"] = Value(kind: VkNamespace, ns: csv_ns)

    DateClass = Value(kind: VkClass, class: new_class("Date"))
    DateClass.class.parent = ObjectClass.class
    DateClass.def_native_method("year", date_year)

    DateTimeClass = Value(kind: VkClass, class: new_class("DateTime"))
    DateTimeClass.class.parent = DateClass.class
    DateTimeClass.def_native_method("elapsed", time_elapsed)

    TimeClass = Value(kind: VkClass, class: new_class("Time"))
    TimeClass.class.parent = ObjectClass.class
    TimeClass.def_native_method("hour", time_hour)

    SelectorClass = Value(kind: VkClass, class: new_class("Selector"))
    SelectorClass.class.parent = ObjectClass.class
    # SelectorClass.ns["descendants"] = ...

    PackageClass = Value(kind: VkClass, class: new_class("Package"))
    PackageClass.class.parent = ObjectClass.class
    PackageClass.def_native_method "name", proc(self: Value, args: Value): Value {.name:"package_name".} =
      self.pkg.name
    GENE_NS.ns["Package"] = PackageClass

    GENE_NS.ns["today"] = Value(kind: VkNativeFn, native_fn: today)
    GENE_NS.ns["now"] = Value(kind: VkNativeFn, native_fn: now)

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
          (@name     = name)
          (@attrs    = attrs)
          (@children = children)
        )

        (method to_s _
          ("<" /@name
            ((/@attrs .map
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
            (if (/@children/.size > 0)
              ("\n"
                ((/@children .join "\n").trim)
              "\n")
            )
            "</" /@name ">"
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
            ((node .@style).merge props)
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

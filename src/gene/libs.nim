import os, osproc, random, base64, json, tables, sequtils, strutils, times, parsecsv, streams, nre
import httpclient
import asyncdispatch, asyncfile, asynchttpserver

import ./types
import ./map_key
import ./interpreter
import ./features/oop
import ./interpreter

proc `%`*(self: Value): JsonNode =
  case self.kind:
  of VkNil:
    return newJNull()
  of VkBool:
    return %self.bool
  of VkInt:
    return %self.int
  of VkString:
    return %self.str
  # of VkSymbol:
  #   return %self.symbol
  of VkVector:
    result = newJArray()
    for item in self.vec:
      result.add(%item)
  of VkMap:
    result = newJObject()
    for k, v in self.map:
      result[k.to_s] = %v
  else:
    todo($self.kind)

proc to_json*(self: Value): string =
  return $(%self)

converter json_to_gene*(node: JsonNode): Value =
  case node.kind:
  of JNull:
    return Nil
  of JBool:
    return node.bval
  of JInt:
    return node.num
  of JFloat:
    return node.fnum
  of JString:
    return node.str
  of JObject:
    result = new_gene_map()
    for k, v in node.fields:
      result.map[k.to_key] = v.json_to_gene
  of JArray:
    result = new_gene_vec()
    for elem in node.elems:
      result.vec.add(elem.json_to_gene)

proc object_class(self: Value, args: Value): Value =
  Value(kind: VkClass, class: self.get_class())

proc object_to_json(self: Value, args: Value): Value =
  self.to_json()

proc object_to_s(self: Value, args: Value): Value =
  self.to_s

proc object_to_bool(self: Value, args: Value): Value =
  self.to_bool

proc class_name(self: Value, args: Value): Value =
  self.class.name

proc class_parent(self: Value, args: Value): Value =
  Value(kind: VkClass, class: self.class.parent)

proc exception_message(self: Value, args: Value): Value =
  self.exception.msg

proc string_size(self: Value, args: Value): Value =
  self.str.len

proc string_to_i(self: Value, args: Value): Value =
  self.str.parse_int

proc string_append(self: Value, args: Value): Value =
  result = self
  for i in 0..<args.gene_data.len:
    self.str.add(args[i].to_s)

proc string_substr(self: Value, args: Value): Value =
  case args.gene_data.len:
  of 1:
    var start = args.gene_data[0].int
    if start >= 0:
      return self.str[start..^1]
    else:
      return self.str[^(-start)..^1]
  of 2:
    var start = args.gene_data[0].int
    var end_index = args.gene_data[1].int
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
  var separator = args.gene_data[0].str
  case args.gene_data.len:
  of 1:
    var parts = self.str.split(separator)
    result = new_gene_vec()
    for part in parts:
      result.vec.add(part)
  of 2:
    var maxsplit = args.gene_data[1].int - 1
    var parts = self.str.split(separator, maxsplit)
    result = new_gene_vec()
    for part in parts:
      result.vec.add(part)
  else:
    not_allowed("split expects 1 or 2 arguments")

proc string_contains(self: Value, args: Value): Value =
  var substr = args.gene_data[0].str
  result = self.str.find(substr) >= 0

proc string_index(self: Value, args: Value): Value =
  var substr = args.gene_data[0].str
  result = self.str.find(substr)

proc string_rindex(self: Value, args: Value): Value =
  var substr = args.gene_data[0].str
  result = self.str.rfind(substr)

proc string_char_at(self: Value, args: Value): Value =
  var i = args.gene_data[0].int
  result = self.str[i]

proc string_trim(self: Value, args: Value): Value =
  result = self.str.strip

proc string_starts_with(self: Value, args: Value): Value =
  var substr = args.gene_data[0].str
  result = self.str.startsWith(substr)

proc string_ends_with(self: Value, args: Value): Value =
  var substr = args.gene_data[0].str
  result = self.str.endsWith(substr)

proc string_to_uppercase(self: Value, args: Value): Value =
  result = self.str.toUpper

proc string_to_lowercase(self: Value, args: Value): Value =
  result = self.str.toLower

proc array_size(self: Value, args: Value): Value =
  result = self.vec.len

proc array_add(self: Value, args: Value): Value =
  self.vec.add(args.gene_data[0])
  result = self

proc array_del(self: Value, args: Value): Value =
  var index = args.gene_data[0].int
  result = self.vec[index]
  self.vec.delete(index)

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

proc gene_data(self: Value, args: Value): Value =
  result = new_gene_vec()
  for item in self.gene_data:
    result.vec.add(item)

proc os_exec(args: Value): Value =
  var cmd = args.gene_data[0].str
  var (output, _) = execCmdEx(cmd)
  result = output

proc file_read(args: Value): Value =
  var file = args.gene_data[0]
  case file.kind:
  of VkString:
    result = read_file(file.str)
  else:
    todo($file.kind)

proc file_read(self: Value, args: Value): Value =
  self.file.read_all()

proc file_read_async(args: Value): Value =
  var file = args.gene_data[0]
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
  var file = args.gene_data[0]
  var content = args.gene_data[1]
  write_file(file.str, content.str)

proc json_parse(args: Value): Value =
  result = args.gene_data[0].str.parse_json

proc csv_parse(args: Value): Value =
  var parser = CsvParser()
  var sep = ','
  # Detect whether it's a tsv (Tab Separated Values)
  if args.gene_data[0].str.contains('\t'):
    sep = '\t'
  parser.open(new_string_stream(args.gene_data[0].str), "unknown.csv", sep)
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
      callback_args.gene_data.add(self.future.read())
      var frame = Frame()
      discard VM.call(frame, args.gene_data[0], callback_args)
  else:
    self.future.add_callback proc() {.gcsafe.} =
      if not self.future.failed:
        var callback_args = new_gene_gene()
        callback_args.gene_data.add(self.future.read())
        var frame = Frame()
        discard VM.call(frame, args.gene_data[0], callback_args)

proc add_failure_callback(self: Value, args: Value): Value =
  # Register callback to future
  if self.future.finished:
    if self.future.failed:
      var callback_args = new_gene_gene()
      var ex = error_to_gene(cast[ref CatchableError](self.future.read_error()))
      callback_args.gene_data.add(ex)
      var frame = Frame()
      discard VM.call(frame, args.gene_data[0], callback_args)
  else:
    self.future.add_callback proc() {.gcsafe.} =
      if self.future.failed:
        var callback_args = new_gene_gene()
        var ex = error_to_gene(cast[ref CatchableError](self.future.read_error()))
        callback_args.gene_data.add(ex)
        var frame = Frame()
        discard VM.call(frame, args.gene_data[0], callback_args)

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    GENE_NS.ns["rand"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_rand".} =
      if args.gene_data.len == 0:
        return new_gene_float(rand(1.0))
      else:
        return rand(args.gene_data[0].int)

    GENE_NS.ns["sleep"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_sleep".} =
      sleep(args.gene_data[0].int)
    GENE_NS.ns["sleep_async"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_sleep_async".} =
      var f = sleep_async(args.gene_data[0].int)
      var future = new_future[Value]()
      f.add_callback proc() {.gcsafe.} =
        future.complete(Nil)
      result = new_gene_future(future)
    GENE_NS.ns["base64"] = new_gene_native_fn proc(args: Value): Value =
      encode(args.gene_data[0].str)
    GENE_NS.ns["run_forever"] = new_gene_native_fn proc(args: Value): Value {.name:"gene_run_forever".} =
      run_forever()

    ObjectClass = Value(kind: VkClass, class: new_class("Object"))
    ObjectClass.def_native_method("class", object_class)
    ObjectClass.def_native_method("to_s", object_to_s)
    ObjectClass.def_native_method("to_json", object_to_json)
    ObjectClass.def_native_method("to_bool", object_to_bool)
    GENE_NS.ns["Object"] = ObjectClass
    GLOBAL_NS.ns["Object"] = ObjectClass

    ClassClass = Value(kind: VkClass, class: new_class("Class"))
    ClassClass.class.parent = ObjectClass.class
    ClassClass.def_native_method("name", class_name)
    ClassClass.def_native_method("parent", class_parent)
    GENE_NS.ns["Class"] = ClassClass
    GLOBAL_NS.ns["Class"] = ClassClass

    ExceptionClass = Value(kind: VkClass, class: new_class("Exception"))
    ExceptionClass.class.parent = ObjectClass.class
    ExceptionClass.def_native_method("message", exception_message)
    GENE_NS.ns["Exception"] = ExceptionClass
    GLOBAL_NS.ns["Exception"] = ExceptionClass

    NamespaceClass = Value(kind: VkClass, class: new_class("Namespace"))
    NamespaceClass.class.parent = ObjectClass.class
    NamespaceClass.def_native_method "name", proc(self: Value, args: Value): Value {.name:"ns_name".} =
      self.ns.name
    GENE_NS.ns["Namespace"] = NamespaceClass
    GLOBAL_NS.ns["Namespace"] = NamespaceClass

    BoolClass = Value(kind: VkClass, class: new_class("Bool"))
    BoolClass.class.parent = ObjectClass.class
    GENE_NS.ns["Bool"] = BoolClass
    GLOBAL_NS.ns["Bool"] = BoolClass

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
      var first = args.gene_data[0]
      var second = args.gene_data[1]
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

    ArrayClass = Value(kind: VkClass, class: new_class("Array"))
    ArrayClass.class.parent = ObjectClass.class
    ArrayClass.def_native_method("size", array_size)
    ArrayClass.def_native_method("add", array_add)
    ArrayClass.def_native_method("del", array_del)
    GENE_NS.ns["Array"] = ArrayClass
    GLOBAL_NS.ns["Array"] = ArrayClass

    MapClass = Value(kind: VkClass, class: new_class("Map"))
    MapClass.class.parent = ObjectClass.class
    MapClass.def_native_method("size", map_size)
    MapClass.def_native_method("keys", map_keys)
    MapClass.def_native_method("values", map_values)
    MapClass.def_native_method "contains", proc(self: Value, args: Value): Value {.name:"map_contains".} =
      self.map.has_key(args.gene_data[0].str.to_key)
    GENE_NS.ns["Map"] = MapClass
    GLOBAL_NS.ns["Map"] = MapClass

    GeneClass = Value(kind: VkClass, class: new_class("Gene"))
    GeneClass.class.parent = ObjectClass.class
    GeneClass.def_native_method("type", gene_type)
    GeneClass.def_native_method("props", gene_props)
    GeneClass.def_native_method("data", gene_data)
    GeneClass.def_native_method "contains", proc(self: Value, args: Value): Value {.name:"gene_contains".} =
      var s = args.gene_data[0].str
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

    GENE_NATIVE_NS.ns["http_get"] = new_gene_native_fn proc(args: Value): Value {.name:"http_get".} =
      var url = args.gene_data[0].str
      var headers = newHttpHeaders()
      for k, v in args.gene_data[2].map:
        headers.add(k.to_s, v.str)
      var client = newHttpClient()
      client.headers = headers
      result = client.get_content(url)

    GENE_NATIVE_NS.ns["http_get_async"] = new_gene_native_fn proc(args: Value): Value {.name:"http_get_async".} =
      var url = args.gene_data[0].str
      var headers = newHttpHeaders()
      for k, v in args.gene_data[2].map:
        headers.add(k.to_s, v.str)
      var client = newAsyncHttpClient()
      client.headers = headers
      var f = client.get_content(url)
      var future = new_future[Value]()
      f.add_callback proc() {.gcsafe.} =
        future.complete(f.read())
      result = new_gene_future(future)

    GENE_NATIVE_NS.ns["http_start_server"] = new_gene_native_fn proc(args: Value): Value {.name:"http_start_server".} =
      var port: int
      if args.gene_data[0].kind == VkString:
        port = args.gene_data[0].str.parse_int
      else:
        port = args.gene_data[0].int
      proc handler(req: Request) {.async gcsafe.} =
        try:
          var options = new_gene_gene(Nil)
          options.gene_data.add(new_gene_any(req.unsafe_addr, HTTP_REQUEST_KEY))
          var body = VM.call_fn(nil, args.gene_data[1], options).str
          await req.respond(Http200, body, new_http_headers())
        except CatchableError as e:
          echo e.msg
          echo e.get_stack_trace()
          discard req.respond(Http500, e.msg, new_http_headers())
      var server = new_async_http_server()
      async_check server.serve(Port(port), handler)

    GENE_NATIVE_NS.ns["http_req_url"] = new_gene_native_method proc(self: Value, args: Value): Value {.name:"http_req_url".} =
      var req = cast[ptr Request](self.any)[]
      result = $req.url

    GENE_NATIVE_NS.ns["http_req_method"] = new_gene_native_method proc(self: Value, args: Value): Value {.name:"http_req_method".} =
      var req = cast[ptr Request](self.any)[]
      result = $req.req_method

    GENE_NATIVE_NS.ns["http_req_params"] = new_gene_native_method proc(self: Value, args: Value): Value {.name:"http_req_params".} =
      result = new_gene_map()
      var req = cast[ptr Request](self.any)[]
      var parts = req.url.query.split('&')
      for p in parts:
        if p == "":
          continue
        var pair = p.split('=', 2)
        result.map[pair[0].to_key] = pair[1]

    discard self.eval """
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
          (s .append (item .to_s) (if (i < (.size)) with))
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

    (ns genex/html
      (class Tag
        (method new [name attrs = {} children = []]
          (@name     = name)
          (@attrs    = attrs)
          (@children = children)
        )

        (method to_s _
          ("<" /@name
            ((/@attrs .map
              ([k v] ->
                (" " k "=\""
                  (if (k == "style")
                    ((v .map ([name value] -> ("" name ":" value ";"))).join)
                  else
                    v
                  )
                  "\""
                )
              )).join)
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
          HTML HEAD TITLE BODY DIV HEADER
          SVG RECT
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

    (ns genex/http
      # Support:
      # HTTP
      # HTTPS
      # Get
      # Post
      # Put
      # Basic auth
      # Headers
      # Cookies
      # Query parameter
      # Post body - application/x-www-form
      # Post body - JSON
      # Response code
      # Response body
      # Response body - JSON

      (fn get [url params = {} headers = {}]
        (gene/native/http_get url params headers)
      )

      (fn ^^async get_async [url params = {} headers = {}]
        (gene/native/http_get_async url params headers)
      )

      (fn get_json [url params = {} headers = {}]
        (gene/json/parse (get url params headers))
      )

      # (var /parse_uri gene/native/http_parse_uri)

      (class Uri
      )

      (class Request
        (method method = gene/native/http_req_method)
        (method url = gene/native/http_req_url)
        (method params = gene/native/http_req_params)
      )

      (class Response
        (method new [code body]
          (@code = code)
          (@body = body)
        )

        (method json _
          ((gene/json/parse @body) .to_json)
        )
      )

      (var /start_server gene/native/http_start_server)
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
    """

import os, base64, json, tables, strutils
import asyncdispatch

import ./types
import ./map_key
import ./interpreter
import ./features/oop

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
  of VkVector:
    result = newJArray()
    for item in self.vec:
      result.add(%item)
  of VkMap:
    result = newJObject()
    for k, v in self.map:
      result[k.to_s] = %v
  else:
    todo()

proc to_json*(self: Value): string =
  return $(%self)

proc object_class(self: Value, args: Value): Value {.nimcall.} =
  Value(kind: VkClass, class: self.get_class())

proc object_to_json(self: Value, args: Value): Value {.nimcall.} =
  self.to_json()

proc object_to_s(self: Value, args: Value): Value {.nimcall.} =
  "TODO: Object.to_s"

proc class_name(self: Value, args: Value): Value {.nimcall.} =
  self.class.name

proc class_parent(self: Value, args: Value): Value {.nimcall.} =
  Value(kind: VkClass, class: self.class.parent)

proc exception_message(self: Value, args: Value): Value {.nimcall.} =
  self.exception.msg

proc string_size(self: Value, args: Value): Value {.nimcall.} =
  self.str.len

proc string_to_i(self: Value, args: Value): Value {.nimcall.} =
  self.str.parse_int

proc string_append(self: Value, args: Value): Value {.nimcall.} =
  result = self
  for i in 0..<args.gene_data.len:
    self.str.add(args[i].to_s)

proc string_substr(self: Value, args: Value): Value {.nimcall.} =
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

proc string_split(self: Value, args: Value): Value {.nimcall.} =
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

proc string_contains(self: Value, args: Value): Value {.nimcall.} =
  var substr = args.gene_data[0].str
  result = self.str.find(substr) >= 0

proc string_index(self: Value, args: Value): Value {.nimcall.} =
  var substr = args.gene_data[0].str
  result = self.str.find(substr)

proc string_rindex(self: Value, args: Value): Value {.nimcall.} =
  var substr = args.gene_data[0].str
  result = self.str.rfind(substr)

proc string_char_at(self: Value, args: Value): Value {.nimcall.} =
  var i = args.gene_data[0].int
  result = self.str[i]

proc string_trim(self: Value, args: Value): Value {.nimcall.} =
  result = self.str.strip

proc string_starts_with(self: Value, args: Value): Value {.nimcall.} =
  var substr = args.gene_data[0].str
  result = self.str.startsWith(substr)

proc string_ends_with(self: Value, args: Value): Value {.nimcall.} =
  var substr = args.gene_data[0].str
  result = self.str.endsWith(substr)

proc string_to_uppercase(self: Value, args: Value): Value {.nimcall.} =
  result = self.str.toUpper

proc string_to_lowercase(self: Value, args: Value): Value {.nimcall.} =
  result = self.str.toLower

proc add_success_callback(self: Value, args: Value): Value {.nimcall.} =
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

proc add_failure_callback(self: Value, args: Value): Value {.nimcall.} =
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
    GENE_NS.ns["sleep"] = new_gene_native_fn proc(args: Value): Value =
      sleep(args.gene_data[0].int)
    GENE_NS.ns["sleep_async"] = new_gene_native_fn proc(args: Value): Value =
      var f = sleep_async(args.gene_data[0].int)
      var future = new_future[Value]()
      f.add_callback proc() {.gcsafe.} =
        future.complete(Nil)
      result = new_gene_future(future)
    GENE_NS.ns["base64"] = new_gene_native_fn proc(args: Value): Value =
      encode(args.gene_data[0].str)

    ObjectClass = Value(kind: VkClass, class: new_class("Object"))
    ObjectClass.def_native_method("class", object_class)
    ObjectClass.def_native_method("to_s", object_to_s)
    ObjectClass.def_native_method("to_json", object_to_json)
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

    FutureClass = Value(kind: VkClass, class: new_class("Future"))
    FutureClass.def_native_method("on_success", add_success_callback)
    FutureClass.def_native_method("on_failure", add_failure_callback)
    FutureClass.class.parent = ObjectClass.class
    GENE_NS.ns["Future"] = FutureClass

    StringClass = Value(kind: VkClass, class: new_class("String"))
    StringClass.class.parent = ObjectClass.class
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
    GENE_NS.ns["String"] = StringClass
    GLOBAL_NS.ns["String"] = StringClass

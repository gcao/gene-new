import os, base64
import asyncdispatch

import ./types
import ./interpreter
import ./features/oop

proc object_to_s(self: Value, args: Value): Value {.nimcall.} =
  "TODO: Object.to_s"

proc exception_message(self: Value, args: Value): Value {.nimcall.} =
  self.exception.msg

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
    ObjectClass.def_native_method("to_s", object_to_s)
    GENE_NS.ns["Object"] = ObjectClass
    GLOBAL_NS.ns["Object"] = ObjectClass

    ClassClass = Value(kind: VkClass, class: new_class("Class"))
    ClassClass.class.parent = ObjectClass.class
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

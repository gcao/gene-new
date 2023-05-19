import tables, std/os
import asyncdispatch

import ../types
import ../interpreter_base

const AWAIT_INTERVAL = 2

type
  ExAsync* = ref object of Expr
    data*: Expr

  ExAwait* = ref object of Expr
    wait_all*: bool
    data*: seq[Expr]

proc eval_async(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExAsync](expr)
  try:
    var val = eval(frame, expr.data)
    if val.kind == VkFuture:
      return val
    var future = new_future[Value]()
    future.complete(val)
    result = new_gene_future(future)
  except system.Exception as e:
    var future = new_future[Value]()
    future.fail(e)
    result = new_gene_future(future)

proc translate_async(value: Value): Expr {.gcsafe.} =
  ExAsync(
    evaluator: eval_async,
    data: translate(value.gene_children),
  )

proc await(self: Value): Value =
    case self.kind:
    of VkFuture:
      while not self.future.finished:
        check_async_ops_and_channel()
        sleep(AWAIT_INTERVAL)
      result = self.future.read()
    else:
      todo()

proc eval_await(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExAwait](expr)
  if expr.wait_all:
    VM.wait_for_futures()
  elif expr.data.len == 1:
    var r = eval(frame, expr.data[0])
    result = await(r)
  else:
    result = new_gene_vec()
    for item in expr.data.mitems:
      var r = eval(frame, item)
      result.vec.add(await(r))

proc translate_await(value: Value): Expr {.gcsafe.} =
  var r = ExAwait(
    evaluator: eval_await,
    wait_all: value.gene_type.str == "$await_all",
  )
  for item in value.gene_children:
    r.data.add(translate(item))
  return r

proc new_future(frame: Frame, args: Value): Value =
  new_gene_future(new_future[Value]())

proc complete(frame: Frame, self: Value, args: Value): Value =
  var v =
    if args.gene_children.len > 0:
      args.gene_children[0]
    else:
      Value(kind: VkNil)

  # Force the dispatcher to process the callbacks
  var future: Future[void]
  if not has_pending_operations():
    future = sleep_async(0)

  self.future.complete(v)

  if not future.is_nil:
    wait_for(future)

proc fail(frame: Frame, self: Value, args: Value): Value =
  var v =
    if args.gene_children.len > 0:
      args.gene_children[0].to_s
    else:
      DEFAULT_ERROR_MESSAGE

  # Force the dispatcher to process the callbacks
  var future: Future[void]
  if not has_pending_operations():
    future = sleep_async(0)

  var e = new_exception(types.Exception, v)
  self.future.fail(e)

  if not future.is_nil:
    wait_for(future)

proc add_success_callback(frame: Frame, self: Value, args: Value): Value =
  # Register callback to future
  if self.future.finished:
    if not self.future.failed:
      var callback_args = new_gene_gene()
      callback_args.gene_children.add(self.future.read())
      var frame = Frame()
      discard call(frame, args.gene_children[0], callback_args)
  else:
    self.future.add_callback proc() {.gcsafe.} =
      if not self.future.failed:
        var callback_args = new_gene_gene()
        callback_args.gene_children.add(self.future.read())
        var frame = Frame()
        discard call(frame, args.gene_children[0], callback_args)

proc add_failure_callback(frame: Frame, self: Value, args: Value): Value =
  # Register callback to future
  if self.future.finished:
    if self.future.failed:
      var callback_args = new_gene_gene()
      var ex = exception_to_value(cast[ref system.Exception](self.future.read_error()))
      callback_args.gene_children.add(ex)
      var frame = Frame()
      discard call(frame, args.gene_children[0], callback_args)
  else:
    self.future.add_callback proc() {.gcsafe.} =
      if self.future.failed:
        var callback_args = new_gene_gene()
        var ex = exception_to_value(cast[ref system.Exception](self.future.read_error()))
        callback_args.gene_children.add(ex)
        var frame = Frame()
        discard call(frame, args.gene_children[0], callback_args)

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["async"] = translate_async
    VM.gene_translators["await"] = translate_await
    VM.gene_translators["$await_all"] = translate_await

    VM.future_class = Value(kind: VkClass, class: new_class("Future"))
    VM.future_class.class.parent = VM.object_class.class
    VM.future_class.def_native_constructor(new_future)
    VM.future_class.def_native_method("complete", complete)
    VM.future_class.def_native_method("fail", fail)
    VM.future_class.def_native_method("on_success", add_success_callback)
    VM.future_class.def_native_method("on_failure", add_failure_callback)
    VM.gene_ns.ns["Future"] = VM.future_class

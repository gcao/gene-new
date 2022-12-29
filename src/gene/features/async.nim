import tables
import asyncdispatch
import threadpool

import ../types
import ../interpreter_base

type
  ExAsync* = ref object of Expr
    data*: Expr

  ExAwait* = ref object of Expr
    wait_all*: bool
    data*: seq[Expr]

proc eval_async(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExAsync](expr)
  try:
    var val = self.eval(frame, expr.data)
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

proc eval_await(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExAwait](expr)
  if expr.wait_all:
    self.wait_for_futures()
  elif expr.data.len == 1:
    var r = self.eval(frame, expr.data[0])
    case r.kind:
    of VkFuture:
      result = wait_for(r.future)
    # of VkThreadResult:
    #   result = ^r.thread_result
    else:
      todo()
  else:
    result = new_gene_vec()
    for item in expr.data.mitems:
      var r = self.eval(frame, item)
      if r.kind == VkFuture:
        result.vec.add(wait_for(r.future))
      else:
        todo()

proc translate_await(value: Value): Expr {.gcsafe.} =
  var r = ExAwait(
    evaluator: eval_await,
    wait_all: value.gene_type.str == "$await_all",
  )
  for item in value.gene_children:
    r.data.add(translate(item))
  return r

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    VM.gene_translators["async"] = translate_async
    VM.gene_translators["await"] = translate_await
    VM.gene_translators["$await_all"] = translate_await

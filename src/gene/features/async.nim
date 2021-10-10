import tables
import asyncdispatch

import ../types
import ../translators

type
  ExAsync* = ref object of Expr
    data*: Expr

  ExAwait* = ref object of Expr
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
  except CatchableError as e:
    var future = new_future[Value]()
    future.fail(e)
    result = new_gene_future(future)

proc translate_async(value: Value): Expr =
  ExAsync(
    evaluator: eval_async,
    data: translate(value.gene_data),
  )

proc eval_await(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExAwait](expr)
  if expr.data.len == 1:
    var r = self.eval(frame, expr.data[0])
    if r.kind == VkFuture:
      result = wait_for(r.future)
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

proc translate_await(value: Value): Expr =
  var r = ExAwait(
    evaluator: eval_await,
  )
  for item in value.gene_data:
    r.data.add(translate(item))
  return r

proc init*() =
  GeneTranslators["async"] = translate_async
  GeneTranslators["await"] = translate_await

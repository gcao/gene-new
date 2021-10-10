import tables
import asyncdispatch

import ../types
import ../translators

type
  ExAsync* = ref object of Expr
    data*: Expr

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

proc init*() =
  GeneTranslators["async"] = translate_async

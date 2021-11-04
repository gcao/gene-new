import tables

import ../types
import ../exprs
import ../translators

type
  ExWith* = ref object of Expr
    self*: Expr
    body*: Expr

  ExDebug* = ref object of Expr
    data*: Value

  ExAssert* = ref object of Expr
    data*: Expr
    message*: Expr

  ExStrings* = ref object of Expr
    first*: string
    rest*: seq[Expr]

proc translate_do(value: Value): Expr =
  var r = ExGroup(
    evaluator: eval_group,
  )
  for item in value.gene_data:
    r.data.add translate(item)
  result = r

proc eval_void(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  for item in cast[ExGroup](expr).data.mitems:
    discard self.eval(frame, item)

proc translate_void(value: Value): Expr =
  var r = ExGroup(
    evaluator: eval_void,
  )
  for item in value.gene_data:
    r.data.add translate(item)
  result = r

proc eval_string(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExStrings](expr)
  var s = ""
  s &= expr.first
  for item in expr.rest.mitems:
    s &= self.eval(frame, item).to_s
  return s

proc translate_string*(value: Value): Expr =
  var e = ExStrings(
    evaluator: eval_string,
  )
  if value.gene_type.kind == VkString:
    e.first = value.gene_type.str
  else:
    e.first = ""

  for item in value.gene_data:
    e.rest.add(translate(item))
  return e

proc eval_with(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var old_self = frame.self
  try:
    frame.self = self.eval(frame, cast[ExWith](expr).self)
    return self.eval(frame, cast[ExWith](expr).body)
  finally:
    frame.self = old_self

proc translate_with(value: Value): Expr =
  ExWith(
    evaluator: eval_with,
    self: translate(value.gene_data[0]),
    body: translate(value.gene_data[1..^1]),
  )

proc eval_assert(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExAssert](expr)
  var value = self.eval(frame, expr.data)
  if not value.to_bool():
    var message = "AssertionFailure: expression returned falsy value."
    if expr.message != nil:
      message = self.eval(frame, expr.message).str
    echo message

proc translate_assert(value: Value): Expr =
  var r = ExAssert(
    evaluator: eval_assert,
    data: translate(value.gene_data[0]),
  )
  if value.gene_data.len > 1:
    r.message = translate(value.gene_data[1])
  return r

proc eval_debug(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExDebug](expr)
  echo "$debug: " & $expr.data
  var e = translate(expr.data)
  result = self.eval(frame, e)
  echo "$debug: " & $expr.data & " => " & $result

proc translate_debug(value: Value): Expr =
  var r = ExDebug(
    evaluator: eval_debug,
  )
  r.data = value.gene_data[0]
  return r

proc init*() =
  GeneTranslators["do"] = translate_do
  GeneTranslators["void"] = translate_void
  GeneTranslators["$"] = translate_string
  GeneTranslators["$with"] = translate_with
  # In IDE, a breakpoint should be set in eval_debug and when running in debug
  # mode, execution should pause and allow the developer to debug the application
  # from there.
  GeneTranslators["$debug"] = translate_debug

  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    GLOBAL_NS.ns["assert"] = new_gene_processor(translate_assert)
    GENE_NS.ns["assert"] = GLOBAL_NS.ns["assert"]

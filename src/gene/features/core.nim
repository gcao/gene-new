import tables

import ../map_key
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

  ExIfMain* = ref object of Expr
    body*: Expr

  ExTap* = ref object of Expr
    value*: Expr
    as_self*: bool
    as_name*: string
    body*: Expr

proc translate_do(value: Value): Expr =
  var r = ExGroup(
    evaluator: eval_group,
  )
  for item in value.gene_children:
    r.children.add translate(item)
  result = r

proc eval_void(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  for item in cast[ExGroup](expr).children.mitems:
    discard self.eval(frame, item)

proc translate_void(value: Value): Expr =
  var r = ExGroup(
    evaluator: eval_void,
  )
  for item in value.gene_children:
    r.children.add translate(item)
  result = r

proc translate_explode(value: Value): Expr =
  var r = new_ex_explode()
  r.data = translate(value.gene_children[0])
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

  for item in value.gene_children:
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
    self: translate(value.gene_children[0]),
    body: translate(value.gene_children[1..^1]),
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
    data: translate(value.gene_children[0]),
  )
  if value.gene_children.len > 1:
    r.message = translate(value.gene_children[1])
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
  r.data = value.gene_children[0]
  return r

proc eval_if_main(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  if VM.main_module == frame.ns.get_module():
    result = self.eval(frame, cast[ExIfMain](expr).body)

proc translate_if_main(value: Value): Expr =
  return ExIfMain(
    evaluator: eval_if_main,
    body: translate(value.gene_children)
  )

proc eval_tap(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExTap](expr)
  result = self.eval(frame, expr.value)
  var old_self = frame.self
  var old_scope = frame.scope
  try:
    frame.scope = new_scope()
    frame.scope.set_parent(old_scope, old_scope.max)
    if expr.as_self:
      frame.self = result
    else:
      frame.scope.def_member(expr.as_name.to_key, result)
    discard self.eval(frame, expr.body)
  finally:
    frame.self = old_self
    frame.scope = old_scope

proc translate_tap(value: Value): Expr =
  var r = ExTap(
    evaluator: eval_tap,
    value: translate(value.gene_children[0]),
  )
  if value.gene_children.len > 1:
    if value.gene_children[1].kind == VkQuote:
      r.as_name = value.gene_children[1].quote.symbol
      if value.gene_children.len > 2:
        r.body = translate(value.gene_children[2..^1])
    else:
      r.as_self = true
      if value.gene_children.len > 1:
        r.body = translate(value.gene_children[1..^1])
  if r.body == nil:
    r.body = translate(@[])
  return r

proc init*() =
  GeneTranslators["do"] = translate_do
  GeneTranslators["void"] = translate_void
  GeneTranslators["..."] = translate_explode
  GeneTranslators["$"] = translate_string
  GeneTranslators["$with"] = translate_with
  # In IDE, a breakpoint should be set in eval_debug and when running in debug
  # mode, execution should pause and allow the developer to debug the application
  # from there.
  GeneTranslators["$debug"] = translate_debug

  # Code that'll be run if current module is the main module
  # Run like "if isMainModule:" in Python
  # It can appear on top level or inside functions etc.
  # Example:
  #   ($if_main
  #     ...
  #   )
  GeneTranslators["$if_main"] = translate_if_main
  GeneTranslators["$tap"] = translate_tap

  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    GLOBAL_NS.ns["assert"] = new_gene_processor(translate_assert)
    GENE_NS.ns["assert"] = GLOBAL_NS.ns["assert"]

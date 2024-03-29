import tables

import ../types
import ../interpreter_base

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

proc translate_do(value: Value): Expr {.gcsafe.} =
  var r = ExGroup(
    evaluator: eval_group,
  )
  for item in value.gene_children:
    r.children.add translate(item)
  result = r

proc translate_noop(value: Value): Expr {.gcsafe.} =
  new_ex_literal(Value(kind: VkNil))

proc eval_void(frame: Frame, expr: var Expr): Value =
  for item in cast[ExGroup](expr).children.mitems:
    discard eval(frame, item)

proc translate_void(value: Value): Expr {.gcsafe.} =
  var r = ExGroup(
    evaluator: eval_void,
  )
  for item in value.gene_children:
    r.children.add translate(item)
  result = r

proc translate_explode(value: Value): Expr {.gcsafe.} =
  var r = new_ex_explode()
  r.data = translate(value.gene_children[0])
  result = r

proc eval_string(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExStrings](expr)
  var s = ""
  s &= expr.first
  for item in expr.rest.mitems:
    s &= eval(frame, item).to_s
  return s

proc translate_string*(value: Value): Expr {.gcsafe.} =
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

proc eval_with(frame: Frame, expr: var Expr): Value =
  var old_self = frame.self
  try:
    frame.self = eval(frame, cast[ExWith](expr).self)
    return eval(frame, cast[ExWith](expr).body)
  finally:
    frame.self = old_self

proc translate_with(value: Value): Expr {.gcsafe.} =
  ExWith(
    evaluator: eval_with,
    self: translate(value.gene_children[0]),
    body: translate(value.gene_children[1..^1]),
  )

proc eval_assert(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExAssert](expr)
  var value = eval(frame, expr.data)
  if not value.to_bool():
    var message = "AssertionFailure: expression returned falsy value."
    if expr.message != nil:
      message = eval(frame, expr.message).str
    echo message

proc translate_assert(value: Value): Expr {.gcsafe.} =
  var r = ExAssert(
    evaluator: eval_assert,
    data: translate(value.gene_children[0]),
  )
  if value.gene_children.len > 1:
    r.message = translate(value.gene_children[1])
  return r

proc eval_debug(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExDebug](expr)
  echo "$debug: " & $expr.data
  var e = translate(expr.data)
  result = eval(frame, e)
  echo "$debug: " & $expr.data & " => " & $result

proc translate_debug(value: Value): Expr {.gcsafe.} =
  var r = ExDebug(
    evaluator: eval_debug,
  )
  r.data = value.gene_children[0]
  return r

proc eval_if_main(frame: Frame, expr: var Expr): Value =
  if VM.app.main_module == frame.ns.get_module():
    result = eval(frame, cast[ExIfMain](expr).body)

proc translate_if_main(value: Value): Expr {.gcsafe.} =
  return ExIfMain(
    evaluator: eval_if_main,
    body: translate(value.gene_children)
  )

proc eval_tap(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExTap](expr)
  result = eval(frame, expr.value)
  var old_self = frame.self
  var old_scope = frame.scope
  try:
    frame.scope = new_scope()
    frame.scope.set_parent(old_scope, old_scope.max)
    if expr.as_self:
      frame.self = result
    else:
      frame.scope.def_member(expr.as_name, result)
    discard eval(frame, expr.body)
  finally:
    frame.self = old_self
    frame.scope = old_scope

proc translate_tap(value: Value): Expr {.gcsafe.} =
  var r = ExTap(
    evaluator: eval_tap,
    value: translate(value.gene_children[0]),
  )
  if value.gene_children.len > 1:
    if value.gene_children[1].kind == VkQuote:
      r.as_name = value.gene_children[1].quote.str
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
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["do"] = translate_do
    VM.gene_translators["noop"] = translate_noop
    VM.gene_translators["void"] = translate_void
    VM.gene_translators["..."] = translate_explode
    VM.gene_translators["$"] = translate_string
    VM.gene_translators["#Str"] = translate_string
    VM.gene_translators["$with"] = translate_with
    # In IDE, a breakpoint should be set in eval_debug and when running in debug
    # mode, execution should pause and allow the developer to debug the application
    # from there.
    VM.gene_translators["$debug"] = translate_debug

    # Code that'll be run if current module is the main module
    # Run like "if isMainModule:" in Python
    # It can appear on top level or inside functions etc.
    # Example:
    #   ($if_main
    #     ...
    #   )
    VM.gene_translators["$if_main"] = translate_if_main
    VM.gene_translators["$tap"] = translate_tap

    let assert = new_gene_processor("assert", translate_assert)
    VM.global_ns.ns["assert"] = assert
    VM.gene_ns.ns["assert"] = assert

    VM.object_class = Value(kind: VkClass, class: new_class("Object"))

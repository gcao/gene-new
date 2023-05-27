import tables

import ../types
import ../interpreter_base

const LOOP_OUTPUT_KEY = "z_loop_output"

type
  ExFor* = ref object of Expr
    name: string
    data: Expr
    body: Expr

  ExFor2* = ref object of Expr
    key_name: string
    val_name: string
    data: Expr
    body: Expr

  ExEmit* = ref object of Expr
    data*: seq[Expr]

proc eval_for(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExFor](expr)
  var old_scope = frame.scope
  try:
    var scope = new_scope()
    scope.set_parent(old_scope, old_scope.max)
    frame.scope = scope

    scope.def_member(expr.name, Value(kind: VkNil))
    var loop_output = new_gene_vec(@[])
    scope.def_member(LOOP_OUTPUT_KEY, loop_output)
    var data = eval(frame, expr.data)
    case data.kind:
    of VkVector:
      for item in data.vec:
        try:
          scope[expr.name] = item
          discard eval(frame, expr.body)
        except Continue:
          continue
        except Break:
          break
    of VkMap:
      for _, v in data.map:
        try:
          scope[expr.name] = v
          discard eval(frame, expr.body)
        except Continue:
          continue
        except Break:
          break
    else:
      todo()

    if loop_output.vec.len > 0:
      result = new_gene_explode(loop_output)

  finally:
    frame.scope = old_scope

proc eval_for2(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExFor2](expr)
  var old_scope = frame.scope
  try:
    var scope = new_scope()
    scope.set_parent(old_scope, old_scope.max)
    frame.scope = scope

    scope.def_member(expr.key_name, Value(kind: VkNil))
    scope.def_member(expr.val_name, Value(kind: VkNil))
    scope.def_member(LOOP_OUTPUT_KEY, @[])
    var data = eval(frame, expr.data)
    case data.kind:
    of VkVector:
      for k, v in data.vec:
        scope[expr.key_name] = k
        scope[expr.val_name] = v
        discard eval(frame, expr.body)
    of VkMap:
      for k, v in data.map:
        scope[expr.key_name] = k.to_s
        scope[expr.val_name] = v
        discard eval(frame, expr.body)
    else:
      todo()
  finally:
    frame.scope = old_scope

proc translate_for(value: Value): Expr {.gcsafe.} =
  if value.gene_children[0].kind == VkVector:
    return ExFor2(
      evaluator: eval_for2,
      key_name: value.gene_children[0].vec[0].str,
      val_name: value.gene_children[0].vec[1].str,
      data: translate(value.gene_children[2]),
      body: translate(value.gene_children[3..^1]),
    )
  else:
    return ExFor(
      evaluator: eval_for,
      name: value.gene_children[0].str,
      data: translate(value.gene_children[2]),
      body: translate(value.gene_children[3..^1]),
    )

proc eval_emit(frame: Frame, expr: var Expr): Value =
  var loop_output = frame.scope[LOOP_OUTPUT_KEY]
  for item in cast[ExEmit](expr).data.mitems:
    loop_output.vec.add(eval(frame, item))

proc translate_emit(value: Value): Expr {.gcsafe.} =
  var r = ExEmit(
    evaluator: eval_emit,
  )
  for item in value.gene_children:
    r.data.add(translate(item))
  return r

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["for"] = translate_for

    let emit = new_gene_processor(translate_emit)
    VM.global_ns.ns["$emit"] = emit
    VM.gene_ns.ns["$emit"] = emit

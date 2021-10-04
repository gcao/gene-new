import tables

import ../types
import ../map_key
import ../translators

let LOOP_OUTPUT_KEY = add_key("z_loop_output")

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

proc eval_for(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExFor](expr)
  var old_scope = frame.scope
  try:
    var scope = new_scope()
    scope.set_parent(old_scope, old_scope.max)
    frame.scope = scope

    scope.def_member(expr.name.to_key, Nil)
    var loop_output = new_gene_vec(@[])
    scope.def_member(LOOP_OUTPUT_KEY, loop_output)
    var data = self.eval(frame, expr.data)
    case data.kind:
    of VkVector:
      for item in data.vec:
        scope[expr.name.to_key] = item
        discard self.eval(frame, expr.body)
    of VkMap:
      for _, v in data.map:
        scope[expr.name.to_key] = v
        discard self.eval(frame, expr.body)
    else:
      todo()

    if loop_output.vec.len > 0:
      result = new_gene_explode(loop_output)

  finally:
    frame.scope = old_scope

proc eval_for2(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExFor2](expr)
  var old_scope = frame.scope
  try:
    var scope = new_scope()
    scope.set_parent(old_scope, old_scope.max)
    frame.scope = scope

    scope.def_member(expr.key_name.to_key, Nil)
    scope.def_member(expr.val_name.to_key, Nil)
    scope.def_member(LOOP_OUTPUT_KEY, @[])
    var data = self.eval(frame, expr.data)
    case data.kind:
    of VkVector:
      for k, v in data.vec:
        scope[expr.key_name.to_key] = k
        scope[expr.val_name.to_key] = v
        discard self.eval(frame, expr.body)
    of VkMap:
      for k, v in data.map:
        scope[expr.key_name.to_key] = k.to_s
        scope[expr.val_name.to_key] = v
        discard self.eval(frame, expr.body)
    else:
      todo()
  finally:
    frame.scope = old_scope

proc translate_for(value: Value): Expr =
  if value.gene_data[0].kind == VkVector:
    return ExFor2(
      evaluator: eval_for2,
      key_name: value.gene_data[0].vec[0].symbol,
      val_name: value.gene_data[0].vec[1].symbol,
      data: translate(value.gene_data[2]),
      body: translate(value.gene_data[3..^1]),
    )
  else:
    return ExFor(
      evaluator: eval_for,
      name: value.gene_data[0].symbol,
      data: translate(value.gene_data[2]),
      body: translate(value.gene_data[3..^1]),
    )

proc eval_emit(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var loop_output = frame.scope[LOOP_OUTPUT_KEY]
  for item in cast[ExEmit](expr).data.mitems:
    loop_output.vec.add(self.eval(frame, item))

proc translate_emit(value: Value): Expr =
  var r = ExEmit(
    evaluator: eval_emit,
  )
  for item in value.gene_data:
    r.data.add(translate(item))
  return r

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    self.app.ns["for"] = new_gene_processor(translate_for)
    self.app.ns["$emit"] = new_gene_processor(translate_emit)

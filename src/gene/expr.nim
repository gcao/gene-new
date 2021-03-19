type
  ExNsDef* = ref object of Expr
    name*: MapKey
    value*: Expr

proc eval_todo*(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  todo()

proc eval_literal(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  cast[ExLiteral](expr).data

proc eval_group(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  for item in cast[ExGroup](expr).data:
    result = item.evaluator(self, frame, item)

proc eval_ns_def(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var e = cast[ExNsDef](expr)
  result = e.value.evaluator(self, frame, e.value)
  frame.ns[e.name] = result

proc new_ex_literal*(v: Value): ExLiteral =
  ExLiteral(
    evaluator: eval_literal,
    data: v,
  )

proc new_ex_group*(): ExGroup =
  result = ExGroup(
    evaluator: eval_group,
  )

proc new_ex_ns_def*(): ExNsDef =
  result = ExNsDef(
    evaluator: eval_ns_def,
  )
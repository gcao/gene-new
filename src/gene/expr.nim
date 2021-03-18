proc eval_todo(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  todo()

proc eval_literal(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  cast[ExLiteral](expr).data

proc eval_group(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  for item in cast[ExGroup](expr).data:
    result = item.evaluator(self, frame, item)

proc new_ex_literal*(v: Value): ExLiteral =
  ExLiteral(
    evaluator: eval_literal,
    data: v,
  )

proc new_ex_group*(): ExGroup =
  result = ExGroup(
    evaluator: eval_group,
  )

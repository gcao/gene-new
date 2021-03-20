# import ./map_key
# import ./types

# #################### Expr ########################

# proc eval_todo*(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
#   todo()

# #################### ExLiteral ###################

# type
#   ExLiteral* = ref object of Expr
#     data*: Value

# proc eval_literal(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
#   cast[ExLiteral](expr).data

# proc new_ex_literal*(v: Value): ExLiteral =
#   ExLiteral(
#     evaluator: eval_literal,
#     data: v,
#   )

# #################### ExGroup #####################

# type
#   ExGroup* = ref object of Expr
#     data*: seq[Expr]

# proc eval_group(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
#   for item in cast[ExGroup](expr).data.mitems:
#     result = item.evaluator(self, frame, item)

# proc new_ex_group*(): ExGroup =
#   result = ExGroup(
#     evaluator: eval_group,
#   )

# #################### ExNsDef #####################

# type
#   ExNsDef* = ref object of Expr
#     name*: MapKey
#     value*: Expr

# proc eval_ns_def(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
#   var e = cast[ExNsDef](expr)
#   result = e.value.evaluator(self, frame, e.value)
#   frame.ns[e.name] = result

# proc new_ex_ns_def*(): ExNsDef =
#   result = ExNsDef(
#     evaluator: eval_ns_def,
#   )

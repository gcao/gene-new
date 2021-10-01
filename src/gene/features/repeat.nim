import ../types
import ../translators

type
  ExRepeat* = ref object of Expr
    times*: Expr
    data: seq[Expr]

proc eval_repeat(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var old_scope = frame.scope
  try:
    var scope = new_scope()
    scope.set_parent(old_scope, old_scope.max)
    frame.scope = scope
    var times = (int)self.eval(frame, cast[ExRepeat](expr).times).int
    var i = 0
    while i < times:
      try:
        i += 1
        for item in cast[ExRepeat](expr).data.mitems:
          discard self.eval(frame, item)
      except Continue:
        discard
      except Break:
        break
  finally:
    frame.scope = old_scope

proc translate_repeat(value: Value): Expr =
  var r = ExRepeat(
    evaluator: eval_repeat,
    times: translate(value.gene_data[0]),
  )
  for item in value.gene_data[1..^1]:
    r.data.add translate(item)
  result = r

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    self.app.ns["repeat"] = new_gene_processor(translate_repeat)

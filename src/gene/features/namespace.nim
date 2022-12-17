import tables

import ../types
import ../interpreter_base
import ./symbol

type
  ExNamespace* = ref object of Expr
    container*: Expr
    name*: string
    body*: Expr

  ExMemberMissing* = ref object of Expr
    data: Expr

proc eval_ns(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExNamespace](expr)
  var ns = new_namespace(frame.ns, e.name)
  result = Value(kind: VkNamespace, ns: ns)
  var container = frame.ns
  if e.container != nil:
    container = self.eval(frame, e.container).ns
  container[e.name] = result

  var new_frame = new_frame()
  new_frame.ns = ns
  new_frame.scope = new_scope()
  new_frame.self = result
  discard self.eval(new_frame, e.body)

proc translate_ns(value: Value): Expr =
  var e = ExNamespace(
    evaluator: eval_ns,
    body: translate(value.gene_children[1..^1]),
  )
  var first = value.gene_children[0]
  case first.kind
  of VkSymbol:
    e.name = first.str
  of VkComplexSymbol:
    e.container = translate(first.csymbol[0..^2])
    e.name = first.csymbol[^1]
  else:
    todo()
  result = e

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    VM.gene_translators["ns"] = translate_ns

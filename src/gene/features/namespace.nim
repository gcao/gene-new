import tables

# import ../map_key
import ../types
import ../exprs
import ../translators
import ../interpreter

type
  ExNamespace* = ref object of Expr
    container*: Expr
    name*: string
    body*: Expr

proc eval_ns(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var e = cast[ExNamespace](expr)
  var ns = new_namespace(e.name)
  ns.parent = frame.ns
  result = Value(kind: VkNamespace, ns: ns)
  var container = frame.ns
  if e.container != nil:
    container = self.eval(frame, e.container).ns
  container[e.name] = result
  var old_self = frame.self
  var old_ns = frame.ns
  try:
    frame.self = result
    frame.ns = ns
    discard self.eval(frame, e.body)
  finally:
    frame.self = old_self
    frame.ns = old_ns

proc translate_ns(value: Value): Expr =
  var e = ExNamespace(
    evaluator: eval_ns,
    body: translate(value.gene_data[1..^1]),
  )
  var first = value.gene_data[0]
  case first.kind
  of VkSymbol:
    e.name = first.symbol
  of VkComplexSymbol:
    e.container = new_ex_names(first.csymbol)
    e.name = first.csymbol.rest[^1]
  else:
    todo()
  result = e

proc init*() =
  GeneTranslators["ns"] = translate_ns

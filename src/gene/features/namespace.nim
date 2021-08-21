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

proc eval_ns(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExNamespace](expr)
  var ns = new_namespace(e.name)
  ns.parent = frame.ns
  result = Value(kind: VkNamespace, ns: ns)
  var container = frame.ns
  if e.container != nil:
    container = self.eval(frame, e.container).ns
  container[e.name] = result

  var new_frame = new_frame()
  new_frame.ns = ns
  new_frame.scope = new_scope()
  new_frame.self = result
  discard self.eval(frame, e.body)

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

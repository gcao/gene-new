import tables

import ../map_key
import ../types
import ../exprs
import ../translators
# import ../interpreter

type
  ExMacro* = ref object of Expr
    data*: Macro

proc eval_macro(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  result = Value(
    kind: VkMacro,
    `macro`: cast[ExMacro](expr).data,
  )
  result.macro.ns = frame.ns

proc to_macro(node: Value): Macro =
  var first = node.gene_data[0]
  var name: string
  if first.kind == VkSymbol:
    name = first.symbol
  elif first.kind == VkComplexSymbol:
    name = first.csymbol.rest[^1]

  var matcher = new_arg_matcher()
  matcher.parse(node.gene_data[1])

  var body: seq[Value] = @[]
  for i in 2..<node.gene_data.len:
    body.add node.gene_data[i]

  body = wrap_with_try(body)
  result = new_macro(name, matcher, body)

proc translate_macro(value: Value): Expr =
  var mac = to_macro(value)
  var expr = new_ex_ns_def()
  expr.name = mac.name.to_key
  expr.value = ExMacro(
    evaluator: eval_macro,
    data: mac,
  )
  return expr

proc init*() =
  GeneTranslators["macro"] = translate_macro

import tables

import ../types
import ../interpreter_base
import ./symbol

type
  ExMacro* = ref object of Expr
    data*: Macro

  ExCallerEval* = ref object of Expr
    data*: Expr

proc eval_macro(frame: Frame, expr: var Expr): Value =
  result = Value(
    kind: VkMacro,
    `macro`: cast[ExMacro](expr).data,
  )
  result.macro.ns = frame.ns

proc to_macro(node: Value): Macro =
  var first = node.gene_children[0]
  var name: string
  if first.kind == VkSymbol:
    name = first.str
  elif first.kind == VkComplexSymbol:
    name = first.csymbol[^1]

  var matcher = new_arg_matcher()
  matcher.parse(node.gene_children[1])

  var body: seq[Value] = @[]
  for i in 2..<node.gene_children.len:
    body.add node.gene_children[i]

  body = wrap_with_try(body)
  result = new_macro(name, matcher, body)

proc translate_macro(value: Value): Expr {.gcsafe.} =
  var mac = to_macro(value)
  var mac_expr = ExMacro(
    evaluator: eval_macro,
    data: mac,
  )
  return translate_definition(value.gene_children[0], mac_expr)

proc eval_caller_eval(frame: Frame, expr: var Expr): Value =
  var v = eval(frame, cast[ExCallerEval](expr).data)
  var e = translate(v)
  eval(frame.parent, e)

proc translate_caller_eval(value: Value): Expr {.gcsafe.} =
  ExCallerEval(
    evaluator: eval_caller_eval,
    data: translate(value.gene_children[0]),
  )

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["macro"] = translate_macro

    VM.global_ns.ns["$caller_eval"] = new_gene_processor(translate_caller_eval)

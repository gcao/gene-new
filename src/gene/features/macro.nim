import tables

import ../map_key
import ../types
import ../interpreter_base
import ./symbol

type
  ExMacro* = ref object of Expr
    data*: Macro

  ExCallerEval* = ref object of Expr
    data*: Expr

proc macro_invoker*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var scope = new_scope()
  scope.set_parent(target.macro.parent_scope, target.macro.parent_scope_max)
  var new_frame = Frame(ns: target.macro.ns, scope: scope)
  new_frame.parent = frame

  var args = cast[ExLiteral](expr).data
  var match_result = self.match(new_frame, target.macro.matcher, args)
  case match_result.kind:
  of MatchSuccess:
    discard
  of MatchMissingFields:
    for field in match_result.missing:
      not_allowed("Argument " & field.to_s & " is missing.")
  else:
    todo()

  if target.macro.body_compiled == nil:
    target.macro.body_compiled = translate(target.macro.body)

  try:
    result = self.eval(new_frame, target.macro.body_compiled)
  except Return as r:
    result = r.val
  except system.Exception as e:
    if self.repl_on_error:
      result = repl_on_error(self, frame, e)
      discard
    else:
      raise

proc eval_macro(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  result = Value(
    kind: VkMacro,
    `macro`: cast[ExMacro](expr).data,
  )
  result.macro.ns = frame.ns

proc arg_translator(value: Value): Expr =
  var expr = new_ex_literal(value)
  expr.evaluator = macro_invoker
  result = expr

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
  result.translator = arg_translator

proc translate_macro(value: Value): Expr =
  var mac = to_macro(value)
  var mac_expr = ExMacro(
    evaluator: eval_macro,
    data: mac,
  )
  return translate_definition(value.gene_children[0], mac_expr)

proc eval_caller_eval(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var v = self.eval(frame, cast[ExCallerEval](expr).data)
  var e = translate(v)
  self.eval(frame.parent, e)

proc translate_caller_eval(value: Value): Expr =
  ExCallerEval(
    evaluator: eval_caller_eval,
    data: translate(value.gene_children[0]),
  )

proc init*() =
  GeneTranslators["macro"] = translate_macro
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    self.global_ns.ns["$caller_eval"] = new_gene_processor(translate_caller_eval)

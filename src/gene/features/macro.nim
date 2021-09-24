import tables

import ../map_key
import ../types
import ../exprs
import ../translators
import ../interpreter

type
  ExMacro* = ref object of Expr
    data*: Macro

proc macro_invoker*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var scope = new_scope()
  scope.set_parent(target.macro.parent_scope, target.macro.parent_scope_max)
  var new_frame = Frame(ns: target.macro.ns, scope: scope)
  new_frame.parent = frame

  var args = cast[ExLiteral](expr).data
  case target.macro.matching_hint.mode:
  of MhNone:
    discard
  of MhSimpleData:
    for _, v in args.gene_props.mpairs:
      todo()
    for i, v in args.gene_data.mpairs:
      let field = target.macro.matcher.children[i]
      new_frame.scope.def_member(field.name, v)
  else:
    for _, v in args.gene_props.mpairs:
      todo()
    for i, v in args.gene_data.mpairs:
      let field = target.macro.matcher.children[i]
      new_frame.scope.def_member(field.name, v)

  if target.macro.body_compiled == nil:
    target.macro.body_compiled = translate(target.macro.body)

  try:
    result = self.eval(new_frame, target.macro.body_compiled)
  except Return as r:
    result = r.val
  # except CatchableError as e:
  #   if self.repl_on_error:
  #     result = repl_on_error(self, frame, e)
  #     discard
  #   else:
  #     raise

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
  result.translator = arg_translator

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
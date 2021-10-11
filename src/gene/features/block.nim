import tables

import ../map_key
import ../types
import ../exprs
import ../translators
import ../interpreter

type
  ExBlock* = ref object of Expr
    data*: Block

proc block_invoker*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var scope = new_scope()
  scope.set_parent(target.block.parent_scope, target.block.parent_scope_max)
  var new_frame = Frame(ns: frame.ns, scope: scope)
  new_frame.parent = frame

  var args = cast[ExLiteral](expr).data
  case target.block.matching_hint.mode:
  of MhSimpleData:
    for _, v in args.gene_props.mpairs:
      todo()
    for i, v in args.gene_data.mpairs:
      let field = target.block.matcher.children[i]
      new_frame.scope.def_member(field.name, v)
  of MhNone:
    discard
  else:
    todo()

  try:
    result = self.eval(new_frame, target.block.body_compiled)
  except Return as r:
    result = r.val
  except CatchableError as e:
    if self.repl_on_error:
      result = repl_on_error(self, frame, e)
      discard
    else:
      raise

proc eval_block(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  result = Value(
    kind: VkBlock,
    `block`: cast[ExBlock](expr).data,
  )
  result.block.frame = frame
  result.block.ns = frame.ns
  result.block.parent_scope = frame.scope
  result.block.parent_scope_max = frame.scope.max

proc arg_translator(value: Value): Expr =
  var expr = new_ex_literal(value)
  expr.evaluator = block_invoker
  result = expr

proc to_block(node: Value): Block =
  var matcher = new_arg_matcher()
  var body: seq[Value] = node.gene_data

  if node.gene_props.has_key(ARGS_KEY):
    matcher.parse(node.gene_props[ARGS_KEY])

  # body = wrap_with_try(body)
  result = new_block(matcher, body)
  result.body_compiled = translate(body)
  result.translator = arg_translator

proc translate_block(value: Value): Expr =
  var blk = to_block(value)
  result = ExBlock(
    evaluator: eval_block,
    data: blk,
  )

proc init*() =
  GeneTranslators["->"] = translate_block

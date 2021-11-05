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
  var expr = cast[ExArguments](expr)
  var scope = new_scope()
  scope.set_parent(target.block.parent_scope, target.block.parent_scope_max)
  var new_frame = Frame(ns: target.block.ns, scope: scope)
  new_frame.parent = frame
  new_frame.self = target.block.frame.self

  handle_args(self, frame, new_frame, target.block.matcher, expr)

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
  var e = new_ex_arg()
  e.evaluator = block_invoker
  for k, v in value.gene_props:
    e.props[k] = translate(v)
  for v in value.gene_data:
    e.data.add(translate(v))
  return e

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

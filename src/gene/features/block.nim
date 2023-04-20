import tables

import ../types
import ../interpreter_base

type
  ExBlock* = ref object of Expr
    data*: Block

proc eval_block(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  result = Value(
    kind: VkBlock,
    `block`: cast[ExBlock](expr).data,
  )
  result.block.frame = frame
  result.block.ns = frame.ns
  result.block.parent_scope = frame.scope
  result.block.parent_scope_max = frame.scope.max

proc to_block(node: Value): Block =
  var matcher = new_arg_matcher()
  var body: seq[Value] = node.gene_children

  if node.gene_props.has_key("args"):
    matcher.parse(node.gene_props["args"])

  # body = wrap_with_try(body)
  result = new_block(matcher, body)
  result.body_compiled = translate(body)

proc translate_block(value: Value): Expr {.gcsafe.} =
  var blk = to_block(value)
  result = ExBlock(
    evaluator: eval_block,
    data: blk,
  )

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    VM.gene_translators["->"] = translate_block

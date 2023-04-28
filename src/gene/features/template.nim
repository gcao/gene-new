import tables

import ../types
import ../interpreter_base

type
  ExRender* = ref object of Expr
    data*: Expr

proc render(frame: Frame, value: var Value): Value =
  case value.kind:
  of VkQuote:
    return value.quote
  of VkUnquote:
    var expr = translate(value.unquote)
    var r = eval(frame, expr)
    if value.unquote_discard:
      return
    else:
      return r
  of VkVector:
    result = new_gene_vec()
    if value.vec.len > 0:
      for item in value.vec.mitems:
        var v = render(frame, item)
        if v == nil:
          discard
        elif v.kind == VkExplode:
          for item in v.explode.vec:
            result.vec.add(item)
        else:
          result.vec.add(v)
    return result
  of VkMap:
    result = new_gene_map()
    for i, item in value.map.mpairs:
      result.map[i] = render(frame, item)
    return result
  of VkGene:
    result = new_gene_gene()
    result.gene_type = render(frame, value.gene_type)
    for key, val in value.gene_props.mpairs:
      result.gene_props[key] = render(frame, val)
    if value.gene_children.len > 0:
      for item in value.gene_children.mitems:
        var v = render(frame, item)
        if v == nil:
          discard
        elif v.kind == VkExplode:
          for item in v.explode.vec:
            result.gene_children.add(item)
        else:
          result.gene_children.add(v)
    return result
  else:
    discard

  value

proc eval_render(frame: Frame, expr: var Expr): Value =
  var old_scope = frame.scope
  try:
    var scope = new_scope()
    scope.set_parent(old_scope, old_scope.max)
    frame.scope = scope

    var v = eval(frame, cast[ExRender](expr).data)
    render(frame, v)
  finally:
    frame.scope = old_scope

proc translate_render(value: Value): Expr {.gcsafe.} =
  ExRender(
    evaluator: eval_render,
    data: translate(value.gene_children[0]),
  )

proc init*() =
  VmCreatedCallbacks.add proc() =
    let render = new_gene_processor(translate_render)
    VM.global_ns.ns["$render"] = render
    VM.gene_ns.ns["$render"] = render

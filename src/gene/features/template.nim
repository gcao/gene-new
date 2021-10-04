import tables

import ../types
import ../map_key
import ../translators

type
  ExRender* = ref object of Expr
    data*: Expr

proc render(self: VirtualMachine, frame: Frame, value: var Value): Value =
  case value.kind:
  of VkVector:
    if value.vec.len > 0:
      var new_data: seq[Value] = @[]
      for item in value.vec.mitems:
        var v = self.render(frame, item)
        if v == nil:
          discard
        elif v.kind == VkExplode:
          for item in v.explode.vec:
            new_data.add(item)
        else:
          new_data.add(v)
      value.vec = new_data
  of VkMap:
    for i, item in value.map.mpairs:
      value.map[i] = self.render(frame, item)
  of VkGene:
    if value.gene_type == Quote:
      return value.gene_data[0]
    if value.gene_data.len > 0:
      var new_data: seq[Value] = @[]
      for item in value.gene_data.mitems:
        var v = self.render(frame, item)
        if v == nil:
          discard
        elif v.kind == VkExplode:
          for item in v.explode.vec:
            new_data.add(item)
        else:
          new_data.add(v)
      value.gene_data = new_data
    for i, item in value.gene_props.mpairs:
      value.gene_props[i] = self.render(frame, item)
    if value.gene_type == Unquote:
      var expr = translate(value.gene_data[0])
      var r = self.eval(frame, expr)
      if value.gene_props.has_key(DISCARD_KEY):
        return
      else:
        return r
    else:
      value.gene_type = self.render(frame, value.gene_type)
  else:
    discard

  value

proc eval_render(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var old_scope = frame.scope
  try:
    var scope = new_scope()
    scope.set_parent(old_scope, old_scope.max)
    frame.scope = scope

    var v = self.eval(frame, cast[ExRender](expr).data)
    self.render(frame, v)
  finally:
    frame.scope = old_scope

proc translate_render(value: Value): Expr =
  ExRender(
    evaluator: eval_render,
    data: translate(value.gene_data[0]),
  )

proc init*() =
  GeneTranslators["$render"] = translate_render

import tables

import ../types
import ../translators

type
  ExRender* = ref object of Expr
    data*: Expr

proc render(self: VirtualMachine, frame: Frame, value: var Value): Value =
  case value.kind:
  of VkVector:
    for i, item in value.vec.mpairs:
      value.vec[i] = self.render(frame, item)
  of VkMap:
    for i, item in value.map.mpairs:
      value.map[i] = self.render(frame, item)
  of VkGene:
    for i, item in value.gene_data.mpairs:
      value.gene_data[i] = self.render(frame, item)
    for i, item in value.gene_props.mpairs:
      value.gene_props[i] = self.render(frame, item)
    if value.gene_type == Unquote:
      var expr = translate(value.gene_data[0])
      return self.eval(frame, expr)
    else:
      value.gene_type = self.render(frame, value.gene_type)
  else:
    discard

  value

proc eval_render(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var v = self.eval(frame, cast[ExRender](expr).data)
  self.render(frame, v)

proc translate_render(value: Value): Expr =
  ExRender(
    evaluator: eval_render,
    data: translate(value.gene_data[0]),
  )

proc init*() =
  GeneTranslators["$render"] = translate_render

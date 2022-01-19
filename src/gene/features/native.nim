import tables

import ../types
import ../exprs
import ../translators

proc eval_native_fn(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var args = new_gene_gene()
  var expr = cast[ExArguments](expr)
  for k, v in expr.props.mpairs:
    args.gene_props[k] = self.eval(frame, v)
  for v in expr.children.mitems:
    args.gene_children.add(self.eval(frame, v))

  case target.kind:
  of VkNativeFn:
    return target.native_fn(args)
  of VkNativeFn2:
    return target.native_fn2(args)
  else:
    todo("eval_native_fn " & $target.kind)

proc native_fn_arg_translator*(value: Value): Expr =
  var e = new_ex_arg()
  e.evaluator = eval_native_fn
  for k, v in value.gene_props:
    e.props[k] = translate(v)
  for v in value.gene_children:
    e.children.add(translate(v))
  return e

proc eval_native_method(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var args = new_gene_gene()
  var expr = cast[ExArguments](expr)
  for k, v in expr.props.mpairs:
    args.gene_props[k] = self.eval(frame, v)
  for v in expr.children.mitems:
    args.gene_children.add(self.eval(frame, v))

  target.native_method(frame.self, args)

proc native_method_arg_translator*(value: Value): Expr =
  var e = new_ex_arg()
  e.evaluator = eval_native_method
  for k, v in value.gene_props:
    e.props[k] = translate(v)
  for v in value.gene_children:
    e.children.add(translate(v))
  return e

proc init*() =
  discard

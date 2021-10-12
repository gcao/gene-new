import tables

import ../types
import ../exprs
import ../translators

proc eval_native_fn(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var args = new_gene_gene()
  var expr = cast[ExArguments](expr)
  for k, v in expr.props.mpairs:
    args.gene_props[k] = self.eval(frame, v)
  for v in expr.data.mitems:
    args.gene_data.add(self.eval(frame, v))

  target.native_fn(args)

proc native_fn_arg_translator*(value: Value): Expr =
  var e = new_ex_arg()
  e.evaluator = eval_native_fn
  for k, v in value.gene_props:
    e.props[k] = translate(v)
  for v in value.gene_data:
    e.data.add(translate(v))
  return e

proc eval_native_method(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var args = new_gene_gene()
  var expr = cast[ExArguments](expr)
  for k, v in expr.props.mpairs:
    args.gene_props[k] = self.eval(frame, v)
  for v in expr.data.mitems:
    args.gene_data.add(self.eval(frame, v))

  target.native_method(frame.self, args)

proc native_method_arg_translator*(value: Value): Expr =
  var e = new_ex_arg()
  e.evaluator = eval_native_method
  for k, v in value.gene_props:
    e.props[k] = translate(v)
  for v in value.gene_data:
    e.data.add(translate(v))
  return e

proc init*() =
  discard

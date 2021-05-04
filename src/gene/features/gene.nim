import tables

import ../map_key
import ../types
import ../normalizers
import ../translators
import ../interpreter

type
  ExGene* = ref object of Expr
    `type`*: Expr
    args*: Value        # The unprocessed args
    args_expr*: Expr    # The translated args

  # ExArgument* = ref object of Expr
  #   props*: Table[MapKey, Value]
  #   data*: seq[Value]

proc should_translate_args*(value: Value): bool =
  true

proc translator*(value: Value): Translator =
  arg_translator

proc process_args*(self: VirtualMachine, frame: Frame, matcher: RootMatcher, args: Value) =
  var match_result = matcher.match(args)
  case match_result.kind:
  of MatchSuccess:
    for field in match_result.fields:
      if field.value_expr != nil:
        frame.scope.def_member(field.name, self.eval(frame, field.value_expr))
      else:
        frame.scope.def_member(field.name, field.value)
  of MatchMissingFields:
    for field in match_result.missing:
      not_allowed("Argument " & field.to_s & " is missing.")
  else:
    todo()

proc function_invoker*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var fn_scope = new_scope()
  fn_scope.set_parent(target.fn.parent_scope, target.fn.parent_scope_max)
  var new_frame = Frame(ns: target.fn.ns, scope: fn_scope)
  new_frame.parent = frame
  new_frame.self = target

  var args = cast[ExArguments](cast[ExGene](expr).args_expr)
  case target.fn.matching_hint.mode:
  of MhSimpleData:
    for _, v in args.props.mpairs:
      discard self.eval(frame, v)
    for i, v in args.data.mpairs:
      let field = target.fn.matcher.children[i]
      new_frame.scope.def_member(field.name, self.eval(frame, v))
  of MhNone:
    for _, v in args.props.mpairs:
      discard self.eval(frame, v)
    for i, v in args.data.mpairs:
      # var field = target.fn.matcher.children[i]
      discard self.eval(frame, v)
  else:
    todo()
    # self.process_args(new_frame, fn.matcher, self.eval(frame, args))

  if target.fn.body_compiled == nil:
    target.fn.body_compiled = translate(target.fn.body)

  try:
    result = self.eval(new_frame, target.fn.body_compiled)
  except Return as r:
    # return's frame is the same as new_frame(current function's frame)
    if r.frame == new_frame:
      result = r.val
    else:
      raise
  # except CatchableError as e:
  #   if self.repl_on_error:
  #     result = repl_on_error(self, frame, e)
  #     discard
  #   else:
  #     raise

proc default_invoker(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  todo()
  # result = new_gene_gene(target)
  # var e = cast[ExGene](expr)
  # for k, v in e.args.mpairs:
  #   result.gene_props[k] = self.eval(frame, v)
  # for v in expr.ex_arg_data.mitems:
  #   result.gene_data.add(self.eval(frame, v))

proc invoker(`type`: Value): Invoker =
  case `type`.kind:
  of VkFunction:
    function_invoker
  else:
    default_invoker

# proc translate_args(value: Value): Expr =
#   todo()

# var DEFAULT_EXTENSION = GeneExtension(
#   translator: translate_args,
#   invoker: default_invoker,
# )

proc eval_gene(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var `type` = self.eval(frame, cast[ExGene](expr).`type`)
  `type`.invoker()(self, frame, `type`, expr)

proc eval_gene_init(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var e = cast[ExGene](expr)
  var `type` = self.eval(frame, e.`type`)

  if `type`.should_translate_args():
    e.args_expr = `type`.translator()(e.args)
  # For future invocations
  expr.evaluator = eval_gene

  `type`.invoker()(self, frame, `type`, expr)

  # if e.extension == nil:
  #   e.extension = Extensions.get_or_default(`type`.kind, DEFAULT_EXTENSION)
  #   expr.ex_gene_value = expr.ex_gene_extension.translator(expr)

  # expr.ex_gene_extension.invoker(self, frame, `type`, expr.ex_gene_value)

# proc eval_args(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
#   result = Value(kind: VkGene)
#   for k, v in expr.ex_arg_props.mpairs:
#     result.gene_props[k] = self.eval(frame, v)
#   for v in expr.ex_arg_data.mitems:
#     result.gene_data.add(self.eval(frame, v))

proc default_translator(value: Value): Expr =
  ExGene(
    evaluator: eval_gene_init,
    `type`: translate(value.gene_type),
    args: value,
  )

proc init*() =
  Translators[VkGene] = proc(value: Value): Expr =
    value.normalize()
    case value.gene_type.kind:
    of VkSymbol:
      var translator = GeneTranslators.get_or_default(value.gene_type.symbol, default_translator)
      return translator(value)
    else:
      return ExGene(
        evaluator: eval_gene_init,
        `type`: translate(value.gene_type),
        args: value,
      )

  # Evaluators[VkExGene.ord] = gene_evaluator
  # Evaluators[VkExArgument.ord] = arg_evaluator

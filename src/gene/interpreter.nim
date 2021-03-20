import strutils, tables, strutils, os

# import ./map_key
import ./types
import ./parser
import ./translators

# var Evaluators*: array[0..2048, Evaluator]
var Extensions* = Table[ValueKind, GeneExtension]()

let GENE_HOME*    = get_env("GENE_HOME", parent_dir(get_app_dir()))
let GENE_RUNTIME* = Runtime(
  home: GENE_HOME,
  name: "default",
  version: read_file(GENE_HOME & "/VERSION").strip(),
)

#################### Definitions #################

proc eval*(self: VirtualMachine, frame: Frame, expr: var Expr): Value {.inline.}

#################### Application #################

proc new_app*(): Application =
  result = Application()
  var global = new_namespace("global")
  result.ns = global

#################### VM ##########################

proc new_vm*(app: Application): VirtualMachine =
  result = VirtualMachine(
    app: app,
  )

proc init_app_and_vm*() =
  var app = new_app()
  VM = new_vm(app)

proc prepare*(self: VirtualMachine, code: string): Value =
  var parsed = read_all(code)
  case parsed.len:
  of 0:
    Nil
  of 1:
    parsed[0]
  else:
    new_gene_stream(parsed)

# proc default_evaluator(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
#   case expr.kind:
#   of VkNil, VkBool, VkInt:
#     result = expr
#   of VkString:
#     result = new_gene_string(expr.str)
#   of VkStream:
#     for e in expr.stream.mitems:
#       result = self.eval(frame, e)
#   else:
#     not_allowed($expr.kind)

# for i in 0..<Evaluators.len:
#   Evaluators[i] = default_evaluator

proc eval*(self: VirtualMachine, frame: Frame, expr: var Expr): Value {.inline.} =
  # var evaluator = Evaluators[expr.kind.ord]
  # evaluator(self, frame, expr)
  expr.evaluator(self, frame, expr)

proc eval*(self: VirtualMachine, code: string): Value =
  var module = new_module()
  var frame = new_frame()
  frame.ns = module.root_ns
  frame.scope = new_scope()
  var expr = translate(self.prepare(code))
  result = self.eval(frame, expr)

#################### Function ####################

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

proc function_invoker*(self: VirtualMachine, frame: Frame, target: Value, args: var Expr): Value =
  var fn = target.fn
  var ns = fn.ns
  var fn_scope = new_scope()
  fn_scope.set_parent(fn.parent_scope, fn.parent_scope_max)
  var new_frame = Frame(ns: ns, scope: fn_scope)
  new_frame.parent = frame
  new_frame.self = target

  case fn.matching_hint.mode:
  of MhSimpleData:
    todo()
    # case args.kind:
    # of VkExArgument:
    #   for _, v in args.ex_arg_props.mpairs:
    #     discard self.eval(frame, v)
    #   for i, v in args.ex_arg_data.mpairs:
    #     var field = fn.matcher.children[i]
    #     new_frame.scope.def_member(field.name, self.eval(frame, v))
    # else:
    #   todo($args.kind)
  of MhNone:
    todo()
    # case args.kind:
    # of VkExArgument:
    #   for _, v in args.ex_arg_props.mpairs:
    #     discard self.eval(frame, v)
    #   for v in args.ex_arg_data.mitems:
    #     discard self.eval(frame, v)
    # else:
    #   todo($args.kind)
  else:
    todo()
    # self.process_args(new_frame, fn.matcher, self.eval(frame, args))

  if fn.body_compiled == nil:
    fn.body_compiled = translate(fn.body)

  try:
    result = self.eval(new_frame, fn.body_compiled)
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

import "./features/core" as core_feature; core_feature.init()
import "./features/array" as array_feature; array_feature.init()
import "./features/map" as map_feature; map_feature.init()
import "./features/gene" as gene_feature; gene_feature.init()
import "./features/quote" as quote_feature; quote_feature.init()
import "./features/arithmetic" as arithmetic_feature; arithmetic_feature.init()
import "./features/var" as var_feature; var_feature.init()
import "./features/assignment" as assignment_feature; assignment_feature.init()
import "./features/if" as if_feature; if_feature.init()
import "./features/fp" as fp_feature; fp_feature.init()
import "./features/namespace" as namespace_feature; namespace_feature.init()

import std/os, sequtils, tables

import ../types
import ../map_key
import ../translators

type
  ExEnv = ref object of Expr
    name*: Expr
    default_value*: Expr

  ExSetEnv = ref object of Expr
    name*: Expr
    value*: Expr

  ExExit = ref object of Expr
    code*: Expr

proc eval_env(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExEnv](expr)
  var env = self.eval(frame, expr.name).to_s
  if exists_env(env):
    result = get_env(env)
  else:
    result = self.eval(frame, expr.default_value).to_s

proc translate_env(value: Value): Expr =
  var r = ExEnv(
    evaluator: eval_env,
    name: translate(value.gene_data[0]),
  )
  if value.gene_data.len > 1:
    r.default_value = translate(value.gene_data[1])
  return r

proc eval_set_env(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExSetEnv](expr)
  var env = self.eval(frame, expr.name).to_s
  var val = self.eval(frame, expr.value).to_s
  put_env(env, val)

proc translate_set_env(value: Value): Expr =
  ExSetEnv(
    evaluator: eval_set_env,
    name: translate(value.gene_data[0]),
    value: translate(value.gene_data[1]),
  )

proc eval_exit(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExExit](expr)
  var code = 0
  if expr.code != nil:
    code = self.eval(frame, expr.code).int
  quit(code)

proc translate_exit(value: Value): Expr =
  var r = ExExit(
    evaluator: eval_exit,
  )
  if value.gene_data.len > 0:
    r.code = translate(value.gene_data[0])
  return r

proc init*() =
  GeneTranslators["exit"] = translate_exit

  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    var cmd_args = command_line_params().map(str_to_gene)
    GLOBAL_NS.ns[CMD_ARGS_KEY] = cmd_args
    GLOBAL_NS.ns["$env"] = new_gene_processor(translate_env)
    GLOBAL_NS.ns["$set_env"] = new_gene_processor(translate_set_env)
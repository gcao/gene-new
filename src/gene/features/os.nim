import std/os, sequtils

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

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    var cmd_args = command_line_params().map(str_to_gene)
    self.app.ns[CMD_ARGS_KEY] = cmd_args
    self.app.ns["$env"] = new_gene_processor(translate_env)
    self.app.ns["$set_env"] = new_gene_processor(translate_set_env)

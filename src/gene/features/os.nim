import std/os, tables

import ../types
import ../interpreter_base

type
  ExEnv = ref object of Expr
    name*: Expr
    default_value*: Expr

  ExSetEnv = ref object of Expr
    name*: Expr
    value*: Expr

  ExExit = ref object of Expr
    code*: Expr

proc eval_env(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExEnv](expr)
  var env = eval(frame, expr.name).to_s
  if exists_env(env):
    result = get_env(env)
  elif expr.default_value != nil:
    result = eval(frame, expr.default_value).to_s
  else:
    result = nil

proc translate_env(value: Value): Expr {.gcsafe.} =
  var r = ExEnv(
    evaluator: eval_env,
    name: translate(value.gene_children[0]),
  )
  if value.gene_children.len > 1:
    r.default_value = translate(value.gene_children[1])
  return r

proc eval_set_env(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExSetEnv](expr)
  var env = eval(frame, expr.name).to_s
  var val = eval(frame, expr.value).to_s
  put_env(env, val)

proc translate_set_env(value: Value): Expr {.gcsafe.} =
  ExSetEnv(
    evaluator: eval_set_env,
    name: translate(value.gene_children[0]),
    value: translate(value.gene_children[1]),
  )

proc eval_exit(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExExit](expr)
  var code = 0
  if expr.code != nil:
    code = eval(frame, expr.code).int
  quit(code)

proc translate_exit(value: Value): Expr {.gcsafe.} =
  var r = ExExit(
    evaluator: eval_exit,
  )
  if value.gene_children.len > 0:
    r.code = translate(value.gene_children[0])
  return r

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.gene_translators["exit"] = translate_exit

    VM.global_ns.ns["$env"] = new_gene_processor(translate_env)
    VM.global_ns.ns["$set_env"] = new_gene_processor(translate_set_env)

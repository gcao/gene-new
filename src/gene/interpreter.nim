import strutils, tables, strutils, os

import ./map_key
import ./types
import ./parser
import ./translators

type
  Evaluator* = proc(self: VirtualMachine, frame: Frame, expr: Value): Value

var Evaluators* = Table[ValueKind, Evaluator]()

let GENE_HOME*    = get_env("GENE_HOME", parent_dir(get_app_dir()))
let GENE_RUNTIME* = Runtime(
  home: GENE_HOME,
  name: "default",
  version: read_file(GENE_HOME & "/VERSION").strip(),
)

#################### Definitions #################

proc eval*(self: VirtualMachine, frame: Frame, node: Value): Value

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

proc default_evaluator(self: VirtualMachine, frame: Frame, expr: Value): Value =
  case expr.kind:
  of VkNil, VkBool, VkInt:
    result = expr
  of VkString:
    result = new_gene_string(expr.str)
  of VkStream:
    for e in expr.stream:
      result = self.eval(frame, e)
  else:
    not_allowed()

proc eval*(self: VirtualMachine, frame: Frame, node: Value): Value =
  var expr = translate(node)
  var evaluator = Evaluators.get_or_default(expr.kind, default_evaluator)
  evaluator(self, frame, expr)

proc eval*(self: VirtualMachine, code: string): Value =
  var module = new_module()
  var frame = new_frame()
  frame.ns = module.root_ns
  frame.scope = new_scope()
  result = self.eval(frame, self.prepare(code))

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

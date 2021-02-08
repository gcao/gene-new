{.experimental: "codeReordering".}

import strutils, sequtils, tables, strutils, parsecsv, streams
import os, osproc, json, httpclient, base64, times, dynlib, uri
import asyncdispatch, asyncfile, asynchttpserver

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

proc eval*(self: VirtualMachine, frame: Frame, expr: Value): Value

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
    translate(parsed[0])
  else:
    translate(new_gene_stream(parsed))

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

proc eval*(self: VirtualMachine, frame: Frame, expr: Value): Value =
  var evaluator = Evaluators.get_or_default(expr.kind, default_evaluator)
  evaluator(self, frame, expr)

proc eval*(self: VirtualMachine, code: string): Value =
  var module = new_module()
  var frame = new_frame()
  frame.ns = module.root_ns
  frame.scope = new_scope()
  result = self.eval(frame, self.prepare(code))

proc init_evaluators*() =
  Evaluators[VkSymbol] = proc(self: VirtualMachine, frame: Frame, expr: Value): Value =
    todo()

init_evaluators()

import "./features/array" as array_feature; array_feature.init()
import "./features/map" as map_feature; map_feature.init()

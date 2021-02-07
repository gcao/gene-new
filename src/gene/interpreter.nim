{.experimental: "codeReordering".}

import strutils, sequtils, tables, strutils, parsecsv, streams
import os, osproc, json, httpclient, base64, times, dynlib, uri
import asyncdispatch, asyncfile, asynchttpserver

import ./map_key
import ./types
import ./parser
import ./translators

let GENE_HOME*    = get_env("GENE_HOME", parent_dir(get_app_dir()))
let GENE_RUNTIME* = Runtime(
  home: GENE_HOME,
  name: "default",
  version: read_file(GENE_HOME & "/VERSION").strip(),
)

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
  translate(parsed[0])

proc eval*(self: VirtualMachine, frame: Frame, expr: Value): Value =
  todo()

proc eval*(self: VirtualMachine, code: string): Value =
  var module = new_module()
  var frame = new_frame()
  frame.ns = module.root_ns
  frame.scope = new_scope()
  result = self.eval(frame, self.prepare(code))

import strutils
import asynchttpserver as stdhttp, asyncdispatch

include gene/ext_common
import gene/interpreter_base

type
  Request = ref object of CustomValue
    req: stdhttp.Request

var RequestClass: Value

# HTTP Server
# https://nim-lang.org/docs/asynchttpserver.html
# https://dev.to/xflywind/write-a-simple-web-framework-in-nim-language-from-scratch-ma0

proc new_gene_request(req: stdhttp.Request): Value =
  Value(
    kind: VkCustom,
    custom: Request(req: req),
    custom_class: RequestClass.class,
  )

proc start_server_internal*(args: Value): Value =
  var port = if args.gene_data[0].kind == VkString:
    args.gene_data[0].str.parse_int
  else:
    args.gene_data[0].int

  proc handler(req: stdhttp.Request) {.async gcsafe.} =
    var my_args = new_gene_gene()
    my_args.gene_data.add(new_gene_request(req))
    # TODO: VM.call is not wrapped
    var body = VM.call(nil, args.gene_data[1], my_args).str
    await req.respond(Http200, body, new_http_headers())

  var server = new_async_http_server()
  async_check server.serve(Port(port), handler)

proc start_server*(args: Value): Value {.wrap_exception.} =
  start_server_internal(args)

{.push dynlib exportc.}

proc init*(): Value {.wrap_exception.} =
  result = new_namespace("http")
  GENEX_NS.ns["http"] = result

  RequestClass = new_gene_class("Request")
  result.ns["Request"] = RequestClass

  result.ns["start_server"] = start_server

{.pop.}

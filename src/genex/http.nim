import strutils
import asynchttpserver as stdhttp, asyncdispatch

include gene/ext_common

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

proc req_method*(self: Value, args: Value): Value {.wrap_exception.} =
  return $cast[Request](self.custom).req.req_method

proc req_url*(self: Value, args: Value): Value {.wrap_exception.} =
  return $cast[Request](self.custom).req.url

proc req_params*(self: Value, args: Value): Value {.wrap_exception.} =
  result = new_gene_map()
  var req = cast[Request](self.custom).req
  var parts = req.url.query.split('&')
  for p in parts:
    if p == "":
      continue
    var pair = p.split('=', 2)
    result.map[pair[0].to_key] = pair[1]

proc start_server_internal*(args: Value): Value =
  var port = if args.gene_data[0].kind == VkString:
    args.gene_data[0].str.parse_int
  else:
    args.gene_data[0].int

  proc handler(req: stdhttp.Request) {.async gcsafe.} =
    echo "HTTP REQ: " & $req.url
    var my_args = new_gene_gene()
    my_args.gene_data.add(new_gene_request(req))
    var res = VM.invoke_catch(nil, args.gene_data[1], my_args)
    if res == nil:
      echo "HTTP RESP: 200, response is nil"
      await req.respond(Http200, "", new_http_headers())
    else:
      case res.kind
      of VkException:
        echo "HTTP RESP: 500 " & res.exception.msg
        echo res.exception.get_stack_trace()
        await req.respond(Http500, "Internal Server Error", new_http_headers())
      of VkString:
        echo "HTTP RESP: 200"
        var body = res.str
        await req.respond(Http200, body, new_http_headers())
      else:
        echo "HTTP RESP: 500 response kind is " & $res.kind
        await req.respond(Http500, "TODO: $res.kind", new_http_headers())

  var server = new_async_http_server()
  async_check server.serve(Port(port), handler)

proc start_server*(args: Value): Value {.wrap_exception.} =
  start_server_internal(args)

{.push dynlib exportc.}

proc init*(): Value {.wrap_exception.} =
  result = new_namespace("http")
  GENEX_NS.ns["http"] = result

  RequestClass = new_gene_class("Request")
  RequestClass.def_native_method "method", method_wrap(req_method)
  RequestClass.def_native_method "url", method_wrap(req_url)
  RequestClass.def_native_method "params", method_wrap(req_params)
  result.ns["Request"] = RequestClass

  result.ns["start_server"] = start_server

{.pop.}

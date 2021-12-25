import strutils, json
import asynchttpserver as stdhttp, asyncdispatch
import httpclient, uri

include gene/extension/boilerplate
import gene/utils

# https://dev.to/xflywind/write-a-simple-web-framework-in-nim-language-from-scratch-ma0
# Ruby Rack: https://github.com/rack/rack/blob/master/SPEC.rdoc
# Python WSGI: https://en.wikipedia.org/wiki/Web_Server_Gateway_Interface
# Clojure Ring: https://github.com/ring-clojure/ring/wiki/Concepts

# HTTP
# HTTPS
# Get/post/put/delete/patch etc
# Basic auth
# Headers
# Cookies
# Query parameter
# Post body - application/x-www-form
# Post body - JSON
# Response code
# Response body
# Response body - JSON

# * Handler
#   Typically looks like this
#   (fn handler req
#     (respond 200 "Hello world!" {^Content-Type "text/plain"})
#   )
#   - Invoked like (handler req)
#   - Anything that can be invoked like (<anything> req) can serve as a handler
#   - Native handlers work similar to gene handlers
#   - A few standard handlers can be provided: e.g.
#     Static asset handler
#     Simple router
#       - Takes a list of handlers, call one by one until a response is reurned.
#       - The insertion order may be important.
#
# * Responder
#   respond will trigger return implicitly?!
#   (respond 500) <=> (return (new Response 500))
#   It can accept a few formats:
#     - code            # int, same as (respond 200, "")
#     - "response body" # same as (respond 200 "response body")
#     - (respond code "response body" headers)
#     - (redirect ...)
#     - Stream
#     - Exception -> will produce a HTTP 500 response and log the exception
#     - What else?
#
# * Middlewares
#   Middlewares are chained
#   Simple middleware looks like:
#   (fn s handler
#     (fnx req
#       (do_something_with req)
#       (var resp (handler req))
#       (do_something_with resp)
#       resp
#     )
#   )
#   Usage: s
#
#   More complex middleware looks like:
#   (fn m x
#     (fnx handler
#       (fnx req
#         (do_something_with req x)
#         (handler req)
#       )
#     )
#   )
#   Usage: (m "something")
#
#   - Native middlewares work similar to gene middlewares
#   - Middlewares usually handles authentication, authorization, response
#     transformation etc
#   - Middlewares can do its work before / after handlers
#     Update request if before handlers
#     Update response if after handlers
#
# * Router
#   - Router is a handler that routes to other handlers
#   - Router usually handles mapping between url patterns and handlers.
#   - Everything a router does can be supported by regular handlers, however
#     a router provides some convenience, e.g. decouple routing and controller
#     logic
#   - Router DSL - it's common to define a dsl to make it easy to implement a router
#   - Routing hierarchy
#

type
  Request = ref object of CustomValue
    req: stdhttp.Request
    props: Table[string, Value]

  Response = ref object of CustomValue
    status: int
    body: Value
    headers: Table[string, Value]
    props: Table[string, Value]

var RequestClass: Value
var ResponseClass: Value

proc new_response*(args: Value): Value {.wrap_exception.} =
  var resp = Response()
  if args.gene_data.len == 0:
    resp.status = 200
  else:
    var first = args.gene_data[0]
    case first.kind:
    of VkInt:
      resp.status = first.int
      if args.gene_data.len > 1:
        resp.body = args.gene_data[1].str
      else:
        resp.body = ""
    of VkString:
      resp.status = 200
      resp.body = first.str
    else:
      todo("new_response " & $first.kind)
  Value(
    kind: VkCustom,
    custom_class: ResponseClass.class,
    custom: resp,
  )

# (respond ...) => (return (new Response ...))
proc translate_respond(value: Value): Expr {.wrap_exception.} =
  var new_value = new_gene_gene(
    new_gene_symbol("return"),
    new_gene_gene(
      new_gene_symbol("new"),
      # # Assume Response class can be accessed thru genex/http/Response
      new_gene_complex_symbol(@["genex", "http", "Response"]),
    ),
  )
  for v in value.gene_data:
    new_value.gene_data[0].gene_data.add(v)
  translate(new_value)

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

proc req_path*(self: Value, args: Value): Value {.wrap_exception.} =
  return $cast[Request](self.custom).req.url.path

proc req_params*(self: Value, args: Value): Value {.wrap_exception.} =
  result = new_gene_map()
  var req = cast[Request](self.custom).req
  var parts = req.url.query.split('&')
  for p in parts:
    if p == "":
      continue
    var pair = p.split('=', 2)
    result.map[pair[0].to_key] = pair[1]

proc req_headers*(self: Value, args: Value): Value {.wrap_exception.} =
  result = new_gene_map()
  var req = cast[Request](self.custom).req
  for key, val in req.headers.pairs:
    result.map[key.to_key] = val

proc resp_status*(self: Value, args: Value): Value {.wrap_exception.} =
  return $cast[Response](self.custom).status

proc start_server_internal*(args: Value): Value =
  var port = if args.gene_data[0].kind == VkString:
    args.gene_data[0].str.parse_int
  else:
    args.gene_data[0].int

  proc handler(req: stdhttp.Request) {.async gcsafe.} =
    echo "HTTP REQ : " & $req.url
    var my_args = new_gene_gene()
    my_args.gene_data.add(new_gene_request(req))
    var res = VM.invoke_catch(nil, args.gene_data[1], my_args)
    if res == nil or res.kind == VkNil:
      echo "HTTP RESP: 404"
      echo()
      await req.respond(Http404, "", new_http_headers())
    else:
      case res.kind
      of VkException:
        echo "HTTP RESP: 500 " & res.exception.msg
        echo res.exception.get_stack_trace()
        echo()
        await req.respond(Http500, "Internal Server Error", new_http_headers())
      of VkString:
        var body = res.str
        echo "HTTP RESP: 200 " & body.abbrev(100)
        echo()
        await req.respond(Http200, body, new_http_headers())
      of VkCustom:
        var resp = cast[Response](res.custom)
        var body = resp.body.str
        echo "HTTP RESP: " & $resp.status & " " & body.abbrev(100)
        echo()
        await req.respond(HttpCode(resp.status), body, new_http_headers())
      else:
        echo "HTTP RESP: 500 response kind is " & $res.kind
        echo()
        await req.respond(Http500, "TODO: $res.kind", new_http_headers())

  var server = new_async_http_server()
  async_check server.serve(Port(port), handler)

proc start_server*(args: Value): Value {.wrap_exception.} =
  start_server_internal(args)

proc http_get(args: Value): Value {.wrap_exception.} =
  var url = args.gene_data[0].str
  var headers = newHttpHeaders()
  if args.gene_data.len > 2:
    for k, v in args.gene_data[2].map:
      headers.add(k.to_s, v.str)
  var client = newHttpClient()
  client.headers = headers
  result = client.get_content(url)

proc http_get_json(args: Value): Value {.wrap_exception.} =
  var url = args.gene_data[0].str
  var headers = newHttpHeaders()
  if args.gene_data.len > 2:
    for k, v in args.gene_data[2].map:
      headers.add(k.to_s, v.str)
  var client = newHttpClient()
  client.headers = headers
  result = client.get_content(url).parse_json

proc http_get_async(args: Value): Value {.wrap_exception.} =
  var url = args.gene_data[0].str
  var headers = newHttpHeaders()
  if args.gene_data.len > 2:
    for k, v in args.gene_data[2].map:
      headers.add(k.to_s, v.str)
  var client = newAsyncHttpClient()
  client.headers = headers
  var f = client.get_content(url)
  var future = new_future[Value]()
  f.add_callback proc() {.gcsafe.} =
    future.complete(f.read())
  result = new_gene_future(future)

{.push dynlib exportc.}

proc init*(module: Module): Value {.wrap_exception.} =
  result = new_namespace("http")
  result.ns.module = module
  GENEX_NS.ns["http"] = result

  result.ns["respond"] = new_gene_processor(translate_wrap(translate_respond))
  result.ns["get"] = http_get
  result.ns["get_json"] = http_get_json
  # result.ns["get_json"] = VM.eval """
  #   (fn get_json [url params = {} headers = {}]
  #     (gene/json/parse (get url params headers))
  #   )
  # """
  # Above code causes GC problem when the http extension is loaded
  # $ examples/http_server.gene
  # Traceback (most recent call last)
  # /Users/gcao/proj/gene/src/genex/http.nim(176) init
  # /Users/gcao/proj/gene/src/gene/interpreter_base.nim(167) eval
  # /Users/gcao/.choosenim/toolchains/nim-1.4.8/lib/system.nim(937) eval
  # /Users/gcao/.choosenim/toolchains/nim-1.4.8/lib/system/arc.nim(169) nimDestroyAndDispose
  # /Users/gcao/.choosenim/toolchains/nim-1.4.8/lib/system/orc.nim(413) nimDecRefIsLastCyclicDyn
  # /Users/gcao/.choosenim/toolchains/nim-1.4.8/lib/system/orc.nim(394) rememberCycle
  # /Users/gcao/.choosenim/toolchains/nim-1.4.8/lib/system/orc.nim(128) unregisterCycle
  # SIGSEGV: Illegal storage access. (Attempt to read from nil?)
  result.ns["get_async"] = http_get_async

  RequestClass = new_gene_class("Request")
  RequestClass.def_native_method "method", method_wrap(req_method)
  RequestClass.def_native_method "url", method_wrap(req_url)
  RequestClass.def_native_method "path", method_wrap(req_path)
  RequestClass.def_native_method "params", method_wrap(req_params)
  RequestClass.def_native_method "headers", method_wrap(req_headers)
  result.ns["Request"] = RequestClass

  ResponseClass = new_gene_class("Response")
  ResponseClass.def_native_constructor(fn_wrap(new_response))
  ResponseClass.def_native_method "status", method_wrap(resp_status)
  result.ns["Response"] = ResponseClass

  result.ns["start_server"] = start_server

{.pop.}

import strutils, tables
import asynchttpserver as stdhttp, asyncdispatch
import httpclient, uri, json as stdjson
import ws # WebSocket library

include gene/extension/boilerplate
import gene/json, gene/utils

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

var RequestClass {.threadvar.}: Value
var ResponseClass {.threadvar.}: Value
var WebSocketClass {.threadvar.}: Value

proc new_response*(frame: Frame, args: Value): Value {.wrap_exception.} =
  var resp = Response()
  if args.gene_children.len == 0:
    resp.status = 200
  else:
    var first = args.gene_children[0]
    case first.kind:
    of VkInt:
      resp.status = first.int
      if args.gene_children.len > 1:
        resp.body = args.gene_children[1].str
      else:
        resp.body = ""
      if args.gene_children.len > 2:
        for k, v in args.gene_children[2].map:
          resp.headers[k.to_s] = v
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
  var new_stmt = new_value.gene_children[0]
  if value.gene_type.str == "redirect":
    new_stmt.gene_children.add(new_gene_int(302))
    new_stmt.gene_children.add(new_gene_string(""))
    new_stmt.gene_children.add(new_gene_map({"Location": value.gene_children[0]}.toTable()))
  else:
    for v in value.gene_children:
      new_stmt.gene_children.add(v)
  translate(new_value)

proc new_gene_request(req: stdhttp.Request): Value =
  Value(
    kind: VkCustom,
    custom: Request(req: req),
    custom_class: RequestClass.class,
  )

proc new_gene_websocket(ws: ws.WebSocket): Value =
  Value(
    kind: VkAny,
    any: ws.unsafe_addr,
    any_class: WebSocketClass.class,
  )

# Copied from Nim 1.6 standard library code
proc handleHexChar*(c: char, x: var int): bool {.inline.} =
  ## Converts `%xx` hexadecimal to the ordinal number and adds the result to `x`.
  ## Returns `true` if `c` is hexadecimal.
  ##
  ## When `c` is hexadecimal, the proc is equal to `x = x shl 4 + hex2Int(c)`.
  runnableExamples:
    var x = 0
    assert handleHexChar('a', x)
    assert x == 10

    assert handleHexChar('B', x)
    assert x == 171 # 10 shl 4 + 11

    assert not handleHexChar('?', x)
    assert x == 171 # unchanged
  result = true
  case c
  of '0'..'9': x = (x shl 4) or (ord(c) - ord('0'))
  of 'a'..'f': x = (x shl 4) or (ord(c) - ord('a') + 10)
  of 'A'..'F': x = (x shl 4) or (ord(c) - ord('A') + 10)
  else:
    result = false

# Copied from Nim 1.6 standard library code
proc decodePercent*(s: openArray[char], i: var int): char =
  ## Converts `%xx` hexadecimal to the character with ordinal number `xx`.
  ##
  ## If `xx` is not a valid hexadecimal value, it is left intact: only the
  ## leading `%` is returned as-is, and `xx` characters will be processed in the
  ## next step (e.g. in `uri.decodeUrl`) as regular characters.
  result = '%'
  if i+2 < s.len:
    var x = 0
    if handleHexChar(s[i+1], x) and handleHexChar(s[i+2], x):
      result = chr(x)
      inc(i, 2)

# Copied from Nim 1.6 standard library code
iterator decodeQuery*(data: string): tuple[key, value: string] =
  ## Reads and decodes query string `data` and yields the `(key, value)` pairs
  ## the data consists of. If compiled with `-d:nimLegacyParseQueryStrict`, an
  ## error is raised when there is an unencoded `=` character in a decoded
  ## value, which was the behavior in Nim < 1.5.1
  runnableExamples:
    import std/sequtils
    assert toSeq(decodeQuery("foo=1&bar=2=3")) == @[("foo", "1"), ("bar", "2=3")]
    assert toSeq(decodeQuery("&a&=b&=&&")) == @[("", ""), ("a", ""), ("", "b"), ("", ""), ("", "")]

  proc parseData(data: string, i: int, field: var string, sep: char): int =
    result = i
    while result < data.len:
      let c = data[result]
      case c
      of '%': add(field, decodePercent(data, result))
      of '+': add(field, ' ')
      of '&': break
      else:
        if c == sep: break
        else: add(field, data[result])
      inc(result)

  var i = 0
  var name = ""
  var value = ""
  # decode everything in one pass:
  while i < data.len:
    setLen(name, 0) # reuse memory
    i = parseData(data, i, name, '=')
    setLen(value, 0) # reuse memory
    if i < data.len and data[i] == '=':
      inc(i) # skip '='
      when defined(nimLegacyParseQueryStrict):
        i = parseData(data, i, value, '=')
      else:
        i = parseData(data, i, value, '&')
    yield (name, value)
    if i < data.len:
      when defined(nimLegacyParseQueryStrict):
        if data[i] != '&':
          uriParseError("'&' expected at index '$#' for '$#'" % [$i, data])
      inc(i)

proc req_method*(frame: Frame, self: Value, args: Value): Value {.wrap_exception.} =
  return $cast[Request](self.custom).req.req_method

proc req_url*(frame: Frame, self: Value, args: Value): Value {.wrap_exception.} =
  return $cast[Request](self.custom).req.url

proc req_path*(frame: Frame, self: Value, args: Value): Value {.wrap_exception.} =
  return $cast[Request](self.custom).req.url.path

proc req_body*(frame: Frame, self: Value, args: Value): Value {.wrap_exception.} =
  return $cast[Request](self.custom).req.body

proc req_body_params*(frame: Frame, self: Value, args: Value): Value {.wrap_exception.} =
  result = new_gene_map()
  var req = cast[Request](self.custom).req
  for k, v in decode_query(req.body):
    result.map[k] = v

proc req_params*(frame: Frame, self: Value, args: Value): Value {.wrap_exception.} =
  result = new_gene_map()
  var req = cast[Request](self.custom).req
  for k, v in decode_query(req.url.query):
    result.map[k] = v

proc req_headers*(frame: Frame, self: Value, args: Value): Value {.wrap_exception.} =
  result = new_gene_map()
  var req = cast[Request](self.custom).req
  for key, val in req.headers.pairs:
    result.map[key] = val

proc resp_status*(frame: Frame, self: Value, args: Value): Value {.wrap_exception.} =
  return $cast[Response](self.custom).status

proc start_server_internal*(frame: Frame, args: Value): Value =
  var port = if args.gene_children[0].kind == VkString:
    args.gene_children[0].str.parse_int
  else:
    args.gene_children[0].int

  let enable_websocket = args.gene_props.has_key("websocket") and args.gene_props["websocket"].map.has_key("path")
  var websocket_path = ""
  var websocket_handler: Value = nil
  if enable_websocket:
    websocket_path = args.gene_props["websocket"].map["path"].str
    websocket_handler = args.gene_props["websocket"].map["handler"]

  proc handler(req: stdhttp.Request) {.async gcsafe.} =
    echo "HTTP REQ : " & $req.req_method & " " & $req.url
    # TODO: catch and handle exceptions
    if req.url.path == websocket_path:
      var ws = await new_web_socket(req)
      var gene_ws = new_gene_websocket(ws)
      while ws.ready_state == Open:
        echo "Waiting for WebSocket message..."
        let packet = await ws.receive_str_packet()
        echo "Received WebSocket message: " & packet
        let payload = parse_json(packet)
        let args = new_gene_gene()
        args.gene_children.add(gene_ws)
        args.gene_children.add(payload)
        discard base.call(frame, websocket_handler, args)

      return

    var my_args = new_gene_gene()
    my_args.gene_children.add(new_gene_request(req))
    var res = invoke_catch(nil, args.gene_children[1], my_args)
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
      # of VkString:
      #   var body = res.str
      #   echo "HTTP RESP: 200 " & body.abbrev(100)
      #   echo()
      #   await req.respond(Http200, body, new_http_headers())
      of VkCustom:
        var resp = cast[Response](res.custom)
        var body = resp.body.str
        echo "HTTP RESP: " & $resp.status & " " & body.abbrev(100)
        echo()
        var headers = new_http_headers()
        for k, v in resp.headers:
          headers.add(k, v.to_s)
        await req.respond(HttpCode(resp.status), body, headers)
      else:
        echo "HTTP RESP: 500 response kind is " & $res.kind
        echo()
        await req.respond(Http500, "TODO: $res.kind", new_http_headers())

  var server = new_async_http_server()
  async_check server.serve(Port(port), handler)

proc start_server*(frame: Frame, args: Value): Value {.wrap_exception.} =
  start_server_internal(frame, args)

proc http_get(frame: Frame, args: Value): Value {.wrap_exception.} =
  var url = args.gene_children[0].str
  var headers = newHttpHeaders()
  if args.gene_children.len > 2:
    for k, v in args.gene_children[2].map:
      headers.add(k.to_s, v.str)
  var client = newHttpClient()
  client.headers = headers
  result = client.get_content(url)

proc http_get_json(frame: Frame, args: Value): Value {.wrap_exception.} =
  var url = args.gene_children[0].str
  var headers = newHttpHeaders()
  if args.gene_children.len > 2:
    for k, v in args.gene_children[2].map:
      headers.add(k.to_s, v.str)
  var client = newHttpClient()
  client.headers = headers
  result = client.get_content(url).parse_json

proc http_get_async(frame: Frame, args: Value): Value {.wrap_exception.} =
  var url = args.gene_children[0].str
  var headers = newHttpHeaders()
  if args.gene_children.len > 2:
    for k, v in args.gene_children[2].map:
      headers.add(k.to_s, v.str)
  var client = newAsyncHttpClient()
  client.headers = headers
  var f = client.get_content(url)
  var future = new_future[Value]()
  f.add_callback proc() {.gcsafe.} =
    future.complete(f.read())
  result = new_gene_future(future)

{.push dynlib exportc.}

proc websocket_send(frame: Frame, self: Value, args: Value): Value {.nimcall, wrap_exception.} =
  var ws = cast[ptr WebSocket](self.any)
  await ws[].send(args.gene_children[0].to_json)

proc init*(module: Module): Value {.wrap_exception.} =
  result = new_namespace("http")
  result.ns.module = module
  VM.genex_ns.ns["http"] = result

  result.ns["respond"] = new_gene_processor(translate_wrap(translate_respond))
  result.ns["redirect"] = new_gene_processor(translate_wrap(translate_respond))
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
  RequestClass.class.parent = VM.object_class.class
  RequestClass.def_native_method "method", method_wrap(req_method)
  RequestClass.def_native_method "url", method_wrap(req_url)
  RequestClass.def_native_method "path", method_wrap(req_path)
  RequestClass.def_native_method "params", method_wrap(req_params)
  RequestClass.def_native_method "body", method_wrap(req_body)
  RequestClass.def_native_method "body_params", method_wrap(req_body_params)
  RequestClass.def_native_method "headers", method_wrap(req_headers)
  result.ns["Request"] = RequestClass

  ResponseClass = new_gene_class("Response")
  ResponseClass.class.parent = VM.object_class.class
  ResponseClass.def_native_constructor(fn_wrap(new_response))
  ResponseClass.def_native_method "status", method_wrap(resp_status)
  result.ns["Response"] = ResponseClass

  WebSocketClass = new_gene_class("WebSocket")
  WebSocketClass.class.parent = VM.object_class.class
  WebSocketClass.def_native_method "send", method_wrap(websocket_send)
  result.ns["WebSocket"] = WebSocketClass

  result.ns["start_server"] = start_server

{.pop.}

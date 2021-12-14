import strutils
import asynchttpserver as stdhttp, asyncdispatch
import httpclient, uri

include gene/extension/boilerplate
import gene/utils

# (ns genex/http
#   # Support:
#   # HTTP
#   # HTTPS
#   # Get
#   # Post
#   # Put
#   # Basic auth
#   # Headers
#   # Cookies
#   # Query parameter
#   # Post body - application/x-www-form
#   # Post body - JSON
#   # Response code
#   # Response body
#   # Response body - JSON

#   (fn get [url params = {} headers = {}]
#     (gene/native/http_get url params headers)
#   )

#   (fn ^^async get_async [url params = {} headers = {}]
#     (gene/native/http_get_async url params headers)
#   )

#   (fn get_json [url params = {} headers = {}]
#     (gene/json/parse (get url params headers))
#   )

#   # (var /parse_uri gene/native/http_parse_uri)

#   (class Uri
#   )

#   (class Request
#     (method method = gene/native/http_req_method)
#     (method url = gene/native/http_req_url)
#     (method params = gene/native/http_req_params)
#   )

#   (class Response
#     (method new [code body]
#       (@code = code)
#       (@body = body)
#     )

#     (method json _
#       ((gene/json/parse @body) .to_json)
#     )
#   )

#   (var /start_server gene/native/http_start_server)
# )

type
  Request = ref object of CustomValue
    req: stdhttp.Request
    props: Table[string, Value]

  Response = ref object of CustomValue
    req: Value
    status: int
    body: Value
    headers: Table[string, Value]
    props: Table[string, Value]

  ExRespond = ref object of Expr
    args: seq[Expr]

var RequestClass: Value
var ResponseClass: Value

# HTTP Server
# https://nim-lang.org/docs/asynchttpserver.html
# https://dev.to/xflywind/write-a-simple-web-framework-in-nim-language-from-scratch-ma0

proc new_gene_response(resp: Response): Value =
  Value(
    kind: VkCustom,
    custom: resp,
    custom_class: ResponseClass.class,
  )

proc eval_respond(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExRespond](expr)
  var resp = Response()
  todo("eval_respond")
  # self.eval(frame, expr.args)
  new_gene_response(resp)

proc translate_respond(value: Value): Expr {.wrap_exception.} =
  var e = ExRespond(
    evaluator: eval_wrap(eval_respond),
  )
  for item in value.gene_data:
    e.args.add(translate(item))
  return e

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
      echo()
      await req.respond(Http200, "", new_http_headers())
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
  GeneTranslators["respond"] = translate_wrap(translate_respond)

  result = new_namespace("http")
  result.ns.module = module
  GENEX_NS.ns["http"] = result

  result.ns["get"] = http_get
  result.ns["get_async"] = http_get_async

  RequestClass = new_gene_class("Request")
  RequestClass.def_native_method "method", method_wrap(req_method)
  RequestClass.def_native_method "url", method_wrap(req_url)
  RequestClass.def_native_method "params", method_wrap(req_params)
  result.ns["Request"] = RequestClass

  ResponseClass = new_gene_class("Response")
  result.ns["Response"] = ResponseClass

  result.ns["start_server"] = start_server

{.pop.}

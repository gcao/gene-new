import tables, nre
import asyncdispatch

import ../gene/types
import ../gene/map_key
import ../gene/interpreter_base

type
  ResourceNotFoundError* = object of types.Exception

  # registry
  Registry* = ref object of CustomValue
    name*: string
    # description*: string
    # props*: Table[string, Value]
    resources_map*: Table[string, Resource]
    resources_by_pattern*: seq[(Regex, Resource)]
    middlewares_before*: seq[Middleware]
    middlewares_around*: seq[Middleware]
    middlewares_after*: seq[Middleware]
    not_found_callbacks*: seq[Value]
    middlewares_cache*: Table[string, (seq[Middleware], seq[Middleware], seq[Middleware])]

  ResourceType* = enum
    RtDefault
    RtOnDemand

  # resource
  Resource* = ref object of CustomValue
    case `type`*: ResourceType
    of RtOnDemand:
      parameterized*: bool
    else:
      discard
    data*: Value
    is_callback*: bool
    dependencies*: seq[string]

  RequestType* = enum
    RqDefault
    RqMultiple

  Request* = ref object of CustomValue
    `type`*: RequestType
    async*: bool
    path*: Value
    params*: Table[MapKey, Value]
    args*: seq[Value]

  ResponseType* = enum
    RsDefault
    RsMultiple
    RsNotFound

  Response* = ref object of CustomValue
    req*: Request
    case `type`*: ResponseType
    of RsDefault:
      value*: Value
    of RsMultiple:
      values*: seq[Value]
    else:
      discard

  MiddlewareType* = enum
    MtBefore
    MtAround
    MtAfter

  # middleware
  Middleware* = ref object of CustomValue
    `type`*: MiddlewareType
    active*: bool
    registry*: Registry
    pos*: int # 0-based index of my position in the list of middlewares
    path*: Value
    callback*: Value

var RegistryClass*   : Value
var RequestClass*    : Value
var ResponseClass*   : Value
var MiddlewareClass* : Value

proc to_response(self: Value): Response =
  if self.is_nil:
    Response(`type`: RsNotFound)
  else:
    Response(`type`: RsDefault, value: self)

proc `[]`*(self: Registry, name: string): Resource =
  if self.resources_map.has_key(name):
    return self.resources_map[name]
  else:
    for pair in self.resources_by_pattern:
      if name.match(pair[0]).is_some():
        return pair[1]

proc add_middleware(self: var Registry, `type`: MiddlewareType, path: Value, callback: Value) =
  var pos = case `type`:
    of MtBefore: self.middlewares_before.len
    of MtAround: self.middlewares_around.len
    of MtAfter: self.middlewares_after.len
  var middleware = Middleware(
    `type`: type,
    active: true,
    registry: self,
    pos: pos,
    path: path,
    callback: callback,
  )
  case `type`:
  of MtBefore:
    self.middlewares_before.add(middleware)
  of MtAround:
    self.middlewares_around.add(middleware)
  of MtAfter:
    self.middlewares_after.add(middleware)

proc call(self: Middleware, req: Request): Response =
  var args = new_gene_gene()
  args.gene_children.add(new_gene_custom(self, MiddlewareClass.class))
  args.gene_children.add(new_gene_custom(req, RequestClass.class))
  var frame = Frame()
  var value = VM.call(frame, self.callback, args)
  return value.to_response()

proc next(self: seq[Middleware], i: int, req: Request): Middleware =
  while i < self.len - 1:
    return self[i + 1]

proc next_applicable(self: Middleware, req: Request): Middleware =
  var pos = self.pos
  case self.type:
  of MtBefore: self.registry.middlewares_before.next(pos, req)
  of MtAround: self.registry.middlewares_around.next(pos, req)
  of MtAfter:  self.registry.middlewares_after .next(pos, req)

proc handle_request(self: Value, req: Value): Response =
  var registry = (Registry)self.custom
  var request = (Request)req.custom
  var resource = registry[request.path.str]
  if resource.is_nil:
    return Response(`type`: RsNotFound)
  elif resource.is_callback:
    var args = new_gene_gene()
    args.gene_children.add(self)
    args.gene_children.add(req)
    var frame = Frame()
    return Response(`type`: RsDefault, value: VM.call(frame, resource.data, args))
  else:
    return Response(`type`: RsDefault, value: resource.data)

proc handle_response(self: var Registry, req: Request, res: Response): Value =
  case res.type:
  of RsNotFound:
    raise new_exception(ResourceNotFoundError, $req.path)
  else:
    return res.value

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    RegistryClass = Value(kind: VkClass, class: new_class("Registry"))
    RequestClass  = Value(kind: VkClass, class: new_class("Request"))
    ResponseClass = Value(kind: VkClass, class: new_class("Response"))
    MiddlewareClass = Value(kind: VkClass, class: new_class("Middleware"))

    self.genex_ns.ns["Registry"] = RegistryClass
    RegistryClass.class.parent = self.object_class.class
    RegistryClass.def_native_constructor proc(args: Value): Value {.name:"registry_new".} =
      var name = ""
      if args.gene_children.len > 0:
        name = args.gene_children[0].to_s
      new_gene_custom(Registry(name: name), RegistryClass.class)

    RegistryClass.def_native_method "name", proc(self: Value, args: Value): Value {.name:"registry_name".} =
      ((Registry)self.custom).name

    RegistryClass.def_native_method "register", proc(self: Value, args: Value): Value {.name:"registry_register".} =
      var resource = Resource(
        data: args.gene_children[1],
      )

      var first = args.gene_children[0]
      case first.kind:
      of VkRegex:
        ((Registry)self.custom).resources_by_pattern.add((first.regex, resource))
      of VkString:
        var path = first.str
        ((Registry)self.custom).resources_map[path] = resource
      else:
        not_allowed("registry_register: " & $first.kind)
    RegistryClass.def_native_method "register_callback", proc(self: Value, args: Value): Value {.name:"registry_register_callback".} =
      var name = args.gene_children[0].str
      var resource = Resource(
        is_callback: true,
        data: args.gene_children[1],
      )
      ((Registry)self.custom).resources_map[name] = resource

    RegistryClass.def_native_method "request", proc(self: Value, args: Value): Value {.name:"registry_request".} =
      var path = args.gene_children[0].str
      var req = Request(
        `type`: RqDefault,
        path: path,
        params: args.gene_props,
        args: args.gene_children[1..^1],
      )

      var req_value = new_gene_custom(req, RequestClass.class)
      var registry = (Registry)self.custom
      var response: Response

      # invokes BEFORE middlewares
      if registry.middlewares_before.len > 0:
        for middleware in registry.middlewares_before:
          var callback = middleware.callback
          var args = new_gene_gene()
          args.gene_children.add(self)
          args.gene_children.add(req_value)
          var frame = Frame()
          discard VM.call(frame, callback, args)

      # invokes AROUND middlewares
      if registry.middlewares_around.len > 0:
        var middleware = registry.middlewares_around[0]
        response = middleware.call(req)
      else:
        response = self.handle_request(req_value)

      # invokes AFTER middlewares
      if registry.middlewares_after.len > 0:
        var res_value = new_gene_custom(response, ResponseClass.class)
        for middleware in registry.middlewares_after:
          var callback = middleware.callback
          var args = new_gene_gene()
          args.gene_children.add(self)
          args.gene_children.add(req_value)
          args.gene_children.add(res_value)
          var frame = Frame()
          discard VM.call(frame, callback, args)

      return registry.handle_response(req, response)

    RegistryClass.def_native_method "req_async", proc(self: Value, args: Value): Value {.name:"registry_req_async".} =
      var name = args.gene_children[0].str
      var future = new_future[Value]()
      result = new_gene_future(future)

      var resource = ((Registry)self.custom)[name]
      if not resource.is_nil:
        future.complete(resource.data)
        return result

      var f = sleep_async(100)
      f.add_callback proc() {.gcsafe.} =
        if not f.failed:
          var resource = ((Registry)self.custom)[name]
          if resource.is_nil:
            f = sleep_async(100)
          else:
            future.complete(resource.data)

    RegistryClass.def_native_method "before", proc(self: Value, args: Value): Value {.name:"registry_before".} =
      var path = args.gene_children[0]
      var callback = args.gene_children[1]
      ((Registry)self.custom).add_middleware(MtBefore, path, callback)

    RegistryClass.def_native_method "around", proc(self: Value, args: Value): Value {.name:"registry_around".} =
      var path = args.gene_children[0]
      var callback = args.gene_children[1]
      ((Registry)self.custom).add_middleware(MtAround, path, callback)

    RegistryClass.def_native_method "after", proc(self: Value, args: Value): Value {.name:"registry_after".} =
      var path = args.gene_children[0]
      var callback = args.gene_children[1]
      ((Registry)self.custom).add_middleware(MtAfter, path, callback)

    ResponseClass.def_native_method "value", proc(self: Value, args: Value): Value {.name:"response_value".} =
      var res = (Response)self.custom
      return res.value

    ResponseClass.def_native_method "set_value", proc(self: Value, args: Value): Value {.name:"response_set_value".} =
      var res = (Response)self.custom
      res.value = args.gene_children[0]

    RequestClass.def_native_method "args", proc(self: Value, args: Value): Value {.name:"request_args".} =
      var req = (Request)self.custom
      return req.args

    RequestClass.def_native_method "not_found", proc(self: Value, args: Value): Value {.name:"request_not_found".} =
      var req = (Request)self.custom
      raise new_exception(ResourceNotFoundError, $req.path)

    MiddlewareClass.def_native_method "call_next", proc(self: Value, args: Value): Value {.name:"middleware_handle".} =
      var middleware = (Middleware)self.custom
      var registry = new_gene_custom(middleware.registry, RegistryClass.class)
      var req = args.gene_children[0]
      if middleware.type != MtAround:
        not_allowed("middleware_handle: " & $middleware.type)
      var next = middleware.next_applicable((Request)req.custom)
      var response: Response
      if next.is_nil:
        response = registry.handle_request(req)
      else:
        response = next.call((Request)req.custom)
      return middleware.registry.handle_response((Request)req.custom, response)

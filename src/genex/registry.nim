import tables
import asyncdispatch

import ../gene/types
import ../gene/map_key
import ../gene/interpreter_base

type
  ResourceNotFoundError* = object of CatchableError

  # registry
  Registry* = ref object of CustomValue
    data*: Table[string, Resource]
    middlewares_before*: seq[Middleware]
    middlewares_around*: seq[Middleware]
    middlewares_after*: seq[Middleware]
    not_found_callbacks*: seq[Value]

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
    dependencies*: seq[string]

  RequestType* = enum
    RqDefault
    RqMultiple

  Request* = ref object of CustomValue
    `type`*: RequestType
    async*: bool
    path*: Value
    props*: Table[MapKey, Value]
    children*: seq[Value]

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
    path*: Value
    callback*: Value

  # Proxy is used by around_callbacks to call the producer or other middlewares
  # to obtain the resource.
  # A proxy stores position of current middleware and can be used to access other
  # middlewares or the producer.
  # (proxy .request) - Will use the original request
  # (proxy .request "path" ...) - Will create a new request object
  Proxy* = ref object of CustomValue
    middleware*: Middleware
    req*: Request

proc `[]`*(self: Registry, name: string): Resource =
  if self.data.has_key(name):
    return self.data[name]

proc add_middleware(self: var Registry, `type`: MiddlewareType, path: Value, callback: Value) =
  var middleware = Middleware(
    `type`: type,
    active: true,
    registry: self,
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

var RegistryClass*   : Value
var RequestClass*    : Value
var ResponseClass*   : Value

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    RegistryClass = Value(kind: VkClass, class: new_class("Registry"))
    RequestClass  = Value(kind: VkClass, class: new_class("Request"))
    ResponseClass = Value(kind: VkClass, class: new_class("Response"))

    GENEX_NS.ns["Registry"] = RegistryClass
    RegistryClass.class.parent = ObjectClass.class
    RegistryClass.def_native_constructor proc(args: Value): Value {.name:"registry_new".} =
      new_gene_custom(Registry(), RegistryClass.class)
    RegistryClass.def_native_method "register", proc(self: Value, args: Value): Value {.name:"registry_register".} =
      var name = args.gene_children[0].str
      var resource = Resource(
        data: args.gene_children[1],
      )
      ((Registry)self.custom).data[name] = resource
    RegistryClass.def_native_method "request", proc(self: Value, args: Value): Value {.name:"registry_request".} =
      var name = args.gene_children[0].str
      var req = Request(`type`: RqDefault, path: name)
      var req_value = new_gene_custom(req, RequestClass.class)
      var registry = (Registry)self.custom
      # TODO: invokes BEFORE middlewares
      # TODO: invokes AROUND middlewares

      var resource = registry.data[name]

      # invokes AFTER middlewares
      if registry.middlewares_after.len > 0:
        var response: Response
        if resource.is_nil:
          response = Response(`type`: RsNotFound)
        else:
          response = Response(`type`: RsDefault, value: resource.data)
        var res_value = new_gene_custom(response, ResponseClass.class)
        for middleware in registry.middlewares_after:
          var callback = middleware.callback
          var args = new_gene_gene()
          args.gene_children.add(self)
          args.gene_children.add(req_value)
          args.gene_children.add(res_value)
          var frame = Frame()
          discard VM.call(frame, callback, args)

        case response.type:
        of RsDefault:
          return response.value
        of RsNotFound:
          raise new_exception(ResourceNotFoundError, name)
        else:
          todo("register_request: " & $response.type)

      else:
        if resource.is_nil:
          raise new_exception(ResourceNotFoundError, name)
        else:
          return resource.data

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
          var resource = ((Registry)self.custom).data[name]
          if resource.is_nil:
            f = sleep_async(100)
          else:
            future.complete(resource.data)

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

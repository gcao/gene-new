import tables
import asyncdispatch

import ../gene/types
import ../gene/map_key

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

  # A proxy stores position of current middleware and can be used to access other
  # middlewares or the producer.
  # (proxy .request) - Will use the original request
  # (proxy .request "path" ...) - Will create a new request object
  Proxy* = ref object of CustomValue
    middleware*: Middleware
    req*: Request

  # middleware
  Middleware* = ref object of CustomValue
    `type`*: MiddlewareType
    active*: bool
    registry*: Registry
    path*: Value
    callback*: Value

proc `[]`*(self: Registry, name: string): Resource =
  if self.data.has_key(name):
    return self.data[name]

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    var klass = Value(kind: VkClass, class: new_class("Registry"))
    GENEX_NS.ns["Registry"] = klass
    klass.class.parent = ObjectClass.class
    klass.def_native_constructor proc(args: Value): Value {.name:"registry_new".} =
      Value(
        kind: VkCustom,
        custom: Registry(),
        custom_class: klass.class,
      )
    klass.def_native_method "register", proc(self: Value, args: Value): Value {.name:"registry_register".} =
      var name = args.gene_children[0].str
      var resource = Resource(
        data: args.gene_children[1],
      )
      ((Registry)self.custom).data[name] = resource
    klass.def_native_method "request", proc(self: Value, args: Value): Value {.name:"registry_request".} =
      var name = args.gene_children[0].str
      var resource = ((Registry)self.custom).data[name]
      if resource.is_nil:
        raise new_exception(ResourceNotFoundError, name)
      else:
        return resource.data
    klass.def_native_method "req_async", proc(self: Value, args: Value): Value {.name:"registry_req_async".} =
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

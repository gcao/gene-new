import tables
import asyncdispatch

import ../gene/types
import ../gene/map_key

type
  ResourceNotFoundError* = object of CatchableError

  ResourceType* = enum
    RtDefault
    RtOnDemand

  Resource* = ref object of CustomValue
    case `type`*: ResourceType
    of RtOnDemand:
      parameterized*: bool
    else:
      discard
    data*: Value
    dependencies*: seq[string]

  Registry* = ref object of CustomValue
    data*: Table[string, Resource]

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

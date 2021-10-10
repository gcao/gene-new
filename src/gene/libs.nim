import tables

import ./types
import ./map_key

proc object_to_s(self: Value, args: Value): Value {.nimcall.} =
  "TODO: Object.to_s"

proc def_native_method(self: Value, name: string, m: NativeMethod) =
  self.class.methods["to_s".to_key] = Method(
    class: self.class,
    name: name,
    callable: Value(kind: VkNativeMethod, native_method: m),
  )

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    ObjectClass = Value(kind: VkClass, class: new_class("Object"))
    ObjectClass.def_native_method("to_s", object_to_s)
    GENE_NS.ns["Object"] = ObjectClass
    ClassClass = Value(kind: VkClass, class: new_class("Class"))
    ClassClass.class.parent = ObjectClass.class
    GENE_NS.ns["Class"] = ClassClass
    ExceptionClass = Value(kind: VkClass, class: new_class("Exception"))
    ExceptionClass.class.parent = ObjectClass.class
    GENE_NS.ns["Exception"] = ExceptionClass

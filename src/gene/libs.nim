import ./types

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    ObjectClass = Value(kind: VkClass, class: new_class("Object"))
    GENE_NS.ns["Object"] = ObjectClass

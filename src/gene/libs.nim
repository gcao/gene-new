import ./types

proc init*() =
  ObjectClass = Value(kind: VkClass, class: new_class("Object"))
  GENE_NS.ns["Object"] = ObjectClass

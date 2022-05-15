import tables

import ./types
import ./parser

type
  Serialization* = ref object
    references*: Table[string, Value]
    data*: Value

  Serializer*   = proc(self: Serialization, value: Value): Value
  Deserializer* = proc(self: Serialization, value: Value): Value

proc serialize*(self: Serialization, value: Value): Value

proc serialize*(value: Value): Serialization =
  result = Serialization(
    references: Table[string, Value](),
  )
  result.data = result.serialize(value)

proc serialize*(self: Serialization, value: Value): Value =
  case value.kind:
  of VkInt, VkString:
    return value
  of VkVector:
    return value
  of VkMap:
    return value
  of VkGene:
    return value
  else:
    todo()

# Class C => "pkgP:modM:nsN/C" or ":modM:nsN/C" or "::nsN/C" or "::C"
proc class_to_path*(class: Class): string =
  todo()

proc path_to_class*(path: string): Class =
  todo()

proc to_s*(self: Serialization): string =
  result = "(gene/Serialization "
  result &= $self.data
  result &= ")"

#################### Deserialization #############

proc deserialize*(self: Serialization, value: Value): Value

proc deserialize*(s: string): Value =
  var ser = Serialization(
    references: Table[string, Value](),
  )
  ser.deserialize(read(s))

proc deserialize*(self: Serialization, value: Value): Value =
  value.gene_children[0]

#################### Expr & eval #################

type
  ExReference* = ref object of Expr
    name*: string
    value*: Expr

proc eval_ref(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  # var expr = cast[ExReference](expr)
  todo()

proc translate_ref(value: Value): Expr =
  var expr = ExReference(
    evaluator: eval_ref,
  )
  return expr

proc eval_ser(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  todo()

proc translate_ser(value: Value): Expr =
  todo()

proc eval_deser(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  todo()

proc translate_deser(value: Value): Expr =
  todo()

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    var serdes = new_namespace("serdes")
    serdes["ref"] = new_gene_processor(translate_ref)
    serdes["serialize"] = new_gene_processor(translate_ser)
    serdes["deserialize"] = new_gene_processor(translate_deser)
    GENE_NS.ns["serdes"] = Value(kind: VkNamespace, ns: serdes)

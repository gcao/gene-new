import tables, strutils

import ./types
import ./parser
import ./interpreter_base

type
  Serialization* = ref object
    references*: Table[string, Value]
    data*: Value

  Serializer*   = proc(self: Serialization, value: Value): Value
  Deserializer* = proc(self: Serialization, value: Value): Value

proc serialize*(self: Serialization, value: Value): Value
proc to_path*(self: Value): string

proc new_ref(path: string): Value =
  new_gene_gene(new_gene_complex_symbol(@["gene", "ref"]), new_gene_string(path))

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
  of VkClass:
    return new_ref(value.to_path())
  else:
    todo()

proc to_path*(self: Module): string =
  return self.name

proc to_path*(self: Namespace): string =
  if self.module.is_nil:
    return self.parent.to_path & "/" & self.name
  else:
    return self.module.to_path & ":"

# Paths can not be inferred for all values.
# When a path can not be inferred, developer should use
# (gene/serdes/ref path value) to explicitly assign a path
# Class C => "pkgP:modM:nsN/C" or ":modM:nsN/C" or "::nsN/C" or "::C"
proc to_path*(self: Value): string =
  case self.kind:
  of VkClass:
    var class = self.class
    return class.ns.parent.to_path & "/" & class.name
  else:
    not_allowed("value_to_path " & $self)

proc path_to_value*(path: string): Value =
  todo()

proc to_s*(self: Serialization): string =
  result = "(gene/serialization "
  result &= $self.data
  result &= ")"

#################### Deserialization #############

proc deserialize*(self: Serialization, vm: VirtualMachine, value: Value): Value

proc deref*(s: string): Value =
  # var parts = s.split(":")
  # var mod_name = parts[0]
  # var local = parts[1]
  # if mod_name =
  todo()

proc deserialize*(vm: VirtualMachine, s: string): Value =
  var ser = Serialization(
    references: Table[string, Value](),
  )
  ser.deserialize(vm, read(s))

proc deserialize*(self: Serialization, vm: VirtualMachine, value: Value): Value =
  case value.kind:
  of VkGene:
    case value.gene_type.kind:
    of VkComplexSymbol:
      case $value.gene_type:
      of "gene/serialization":
        return self.deserialize(vm, value.gene_children[0])
      of "gene/ref":
        todo()
      else:
        return value
    else:
      return value
  else:
    return value

#################### Expr & eval #################

type
  ExSer* = ref object of Expr
    value*: Expr

  ExDeser* = ref object of Expr
    value*: Expr

proc eval_ser(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExSer](expr)
  return serialize(self.eval(frame, expr.value)).to_s

proc translate_ser(value: Value): Expr =
  return ExSer(
    evaluator: eval_ser,
    value: translate(value.gene_children[0]),
  )

proc eval_deser(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExDeser](expr)
  return self.deserialize(self.eval(frame, expr.value).str)

proc translate_deser(value: Value): Expr =
  return ExDeser(
    evaluator: eval_deser,
    value: translate(value.gene_children[0]),
  )

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    var serdes = new_namespace("serdes")
    serdes["serialize"] = new_gene_processor(translate_ser)
    serdes["deserialize"] = new_gene_processor(translate_deser)
    GENE_NS.ns["serdes"] = Value(kind: VkNamespace, ns: serdes)

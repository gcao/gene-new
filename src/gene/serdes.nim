import tables

import ./types
import ./parser

type
  Serialization* = ref object
    types*: Table[string, SerdesBase]
    data*: Value

  SerdesBase* = ref object of RootObj
    serializer*: Serializer
    deserializer*: Deserializer

  Serializer*   = proc(self: Serialization, value: Value): Value
  Deserializer* = proc(self: Serialization, value: Value): Value

proc serialize*(self: Serialization, value: Value): Value

proc serialize*(value: Value): Serialization =
  result = Serialization(
    types: Table[string, SerdesBase](),
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

proc to_s*(self: Serialization): string =
  result = "(gene/Serialization "
  result &= $self.data
  result &= ")"

#################### Deserialization #############

proc deserialize*(self: Serialization, value: Value): Value

proc deserialize*(s: string): Value =
  var ser = Serialization(
    types: Table[string, SerdesBase](),
  )
  ser.deserialize(read(s))

proc deserialize*(self: Serialization, value: Value): Value =
  value.gene_children[0]

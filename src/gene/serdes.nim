import tables

import ./types
import ./parser

type
  Serialization* = ref object
    types*: Table[string, Value]
    data*: string

proc serialize*(self: Serialization, value: Value): string

proc serialize*(value: Value): Serialization =
  result = Serialization(
    types: Table[string, Value](),
  )
  result.data = result.serialize(value)

proc serialize*(self: Serialization, value: Value): string =
  case value.kind:
  of VkInt:
    return $value
  else:
    todo()

proc to_s*(self: Serialization): string =
  result = "(gene/Serialization "
  result &= self.data
  result &= ")"

#################### Deserialization #############

proc deserialize*(s: string): Value =
  var parsed = read(s)
  parsed.gene_children[0]

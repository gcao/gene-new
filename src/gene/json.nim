import tables, std/json

import ./types

export parse_json

proc `%`*(self: Value): JsonNode =
  case self.kind:
  of VkNil:
    return newJNull()
  of VkBool:
    return %self.bool
  of VkInt:
    return %self.int
  of VkString:
    return %self.str
  # of VkSymbol:
  #   return %self.str
  of VkVector:
    result = newJArray()
    for item in self.vec:
      result.add(%item)
  of VkMap:
    result = newJObject()
    for k, v in self.map:
      result[k] = %v
  else:
    todo($self.kind)

converter json_to_gene*(node: JsonNode): Value =
  case node.kind:
  of JNull:
    return Value(kind: VkNil)
  of JBool:
    return node.bval
  of JInt:
    return node.num
  of JFloat:
    return node.fnum
  of JString:
    return node.str
  of JObject:
    result = new_gene_map()
    for k, v in node.fields:
      result.map[k] = v.json_to_gene
  of JArray:
    result = new_gene_vec()
    for elem in node.elems:
      result.vec.add(elem.json_to_gene)

proc to_json*(self: Value): string =
  return $(%self)

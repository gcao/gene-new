import tables, strutils

import ./types
import ./parser
import ./interpreter_base

type
  Serialization* = ref object
    references*: Table[string, Value]
    data*: Value

proc serialize*(self: Serialization, value: Value): Value {.gcsafe.}
proc to_path*(self: Value): string {.gcsafe.}
proc to_path*(self: Class): string {.gcsafe.}

proc new_ref(path: string): Value =
  new_gene_gene(new_gene_complex_symbol(@["gene", "ref"]), new_gene_string(path))

# For values not serializable, there are several ways to handle it:
# 1. throw an error and abort during serialization
# 2. replace unserializable value with some special value, throw an error
#    when the special value was used/invoked etc.
# 3. replace with nil
#
# These can be controlled by options passed in.

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
  of VkClass, VkFunction:
    return new_ref(value.to_path())
  of VkInstance:
    result = new_gene_gene(new_gene_complex_symbol(@["gene", "instance"]))
    result.gene_children.add(new_ref(value.instance_class.to_path()))
    var props = new_gene_map()
    for k, v in value.instance_props:
      props.map[k] = self.serialize(v)
    result.gene_children.add(props)
  else:
    todo()

proc to_path*(self: Module): string =
  self.name

proc to_path*(self: Namespace): string =
  if self.module.is_nil:
    return self.parent.to_path & "/" & self.name
  else:
    return self.module.to_path & ":"

proc to_path*(self: Class): string =
  self.ns.parent.to_path & "/" & self.name

# A path looks like
# Class C => "pkgP:modM:nsN/C"
# Paths can not be inferred for all values.
# When a path can not be inferred, developer should use
# (gene/serdes/ref path value) to explicitly assign a path
proc to_path*(self: Value): string =
  case self.kind:
  of VkClass:
    return self.class.to_path()
  of VkFunction:
    return self.fn.ns.to_path() & "/" & self.fn.name
  else:
    not_allowed("value_to_path " & $self)

proc path_to_value*(path: string): Value =
  todo()

proc to_s*(self: Serialization): string =
  result = "(gene/serialization "
  result &= $self.data
  result &= ")"

#################### Deserialization #############

proc deserialize*(self: Serialization, value: Value): Value {.gcsafe.}

proc deref*(self: Serialization, s: string): Value =
  var parts = s.split(":")
  var module_name = parts[0]
  var ns_path = parts[1].split("/")
  var ns = VM.modules[module_name]
  while ns_path.len > 1:
    ns_path.delete(0)
    var key = ns_path[0]
    result = ns[key]
    if ns_path.len > 1:
      case result.kind:
      of VkNamespace:
        ns = result.ns
      of VkClass:
        ns = result.class.ns
      else:
        not_allowed("deref " & s & " " & $result.kind)

proc deserialize*(s: string): Value =
  var ser = Serialization(
    references: Table[string, Value](),
  )
  ser.deserialize(read(s))

proc deserialize*(self: Serialization, value: Value): Value =
  case value.kind:
  of VkGene:
    case value.gene_type.kind:
    of VkComplexSymbol:
      case $value.gene_type:
      of "gene/serialization":
        return self.deserialize(value.gene_children[0])
      of "gene/ref":
        return self.deref(value.gene_children[0].str)
      of "gene/instance":
        var class = self.deserialize(value.gene_children[0]).class
        var props = Table[string, Value]()
        for k, v in value.gene_children[1].map:
          props[k] = self.deserialize(v)
        return new_gene_instance(class, props)
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

proc eval_ser(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExSer](expr)
  return serialize(eval(frame, expr.value)).to_s

proc translate_ser(value: Value): Expr {.gcsafe.} =
  return ExSer(
    evaluator: eval_ser,
    value: translate(value.gene_children[0]),
  )

proc eval_deser(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExDeser](expr)
  return deserialize(eval(frame, expr.value).str)

proc translate_deser(value: Value): Expr {.gcsafe.} =
  return ExDeser(
    evaluator: eval_deser,
    value: translate(value.gene_children[0]),
  )

proc init*() =
  VmCreatedCallbacks.add proc() =
    var serdes = new_namespace("serdes")
    serdes["serialize"] = new_gene_processor(translate_ser)
    serdes["deserialize"] = new_gene_processor(translate_deser)
    VM.gene_ns.ns["serdes"] = Value(kind: VkNamespace, ns: serdes)

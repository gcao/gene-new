import strutils, tables

import ./map_key
import ./types

const ASSIGNMENT_OPS = [
  "=", "+=", "-=", "*=", "/=", "**=",
  "&&=", "||=",
]

type
  Normalizer* = proc(self: Value): bool

var Normalizers: seq[Normalizer]

# Important: order of normalizers matters. normalize() should be tested as a whole

Normalizers.add proc(self: Value): bool =
  var `type` = self.gene_type
  if `type`.kind == VkSymbol:
    if `type`.symbol == ".":
      self.gene_props[SELF_KEY] = new_gene_symbol("self")
      self.gene_props[METHOD_KEY] = self.gene_children[0]
      self.gene_children.delete 0
      self.gene_type = new_gene_symbol("$invoke_dynamic")
    elif `type`.symbol[0] == '.' and `type`.symbol != "...":  # (.method x y z)
      self.gene_props[SELF_KEY] = new_gene_symbol("self")
      self.gene_props[METHOD_KEY] = new_gene_string_move(`type`.symbol.substr(1))
      self.gene_type = new_gene_symbol("$invoke_method")

# Normalizers.add proc(self: Value): bool =
#   var `type` = self.gene_type
#   if `type`.kind == VkSymbol:
#     if `type`.symbol == "import":
#       var names: seq[Value] = @[]
#       var module: Value
#       var expect_module = false
#       for val in self.gene_children:
#         if expect_module:
#           module = val
#         elif val.kind == VkSymbol and val.symbol == "from":
#           expect_module = true
#         else:
#           names.add(val)
#       self.gene_props[NAMES_KEY] = new_gene_vec(names)
#       self.gene_props[MODULE_KEY] = module
#       return true

# Normalizers.add proc(self: Value): bool =
#   if self.gene_type.kind == VkSymbol:
#     if self.gene_type.symbol == "fnx":
#       self.gene_type = new_gene_symbol("fn")
#       self.gene_children.insert(new_gene_symbol("_"), 0)
#       return true
#     elif self.gene_type.symbol == "fnxx":
#       self.gene_type = new_gene_symbol("fn")
#       self.gene_children.insert(new_gene_symbol("_"), 0)
#       self.gene_children.insert(new_gene_symbol("_"), 0)
#       return true

Normalizers.add proc(self: Value): bool =
  if self.gene_children.len < 1:
    return false
  var `type` = self.gene_type
  var first = self.gene_children[0]
  if first.kind == VkSymbol:
    if first.symbol == "=" and `type`.kind == VkSymbol and `type`.symbol.startsWith("@"):
      # (@prop = val)
      self.gene_type = new_gene_symbol("$set")
      self.gene_children[0] = `type`
      self.gene_children.insert(new_gene_symbol("self"), 0)
      return true

proc handle_assignment_shortcuts(self: seq[Value]): Value =
  if self.len mod 2 == 0:
    raise new_gene_exception("Invalid right value for assignment " & $self)
  if self.len == 1:
    return self[0]
  if self[1].kind == VkSymbol and self[1].symbol in ASSIGNMENT_OPS:
    result = new_gene_gene(self[1])
    result.gene_children.add(self[0])
    result.gene_children.add(handle_assignment_shortcuts(self[2..^1]))
  else:
    raise new_gene_exception("Invalid right value for assignment " & $self)

Normalizers.add proc(self: Value): bool =
  if self.gene_children.len < 1:
    return false
  var first = self.gene_children[0]
  if first.kind == VkSymbol and first.symbol in ASSIGNMENT_OPS:
    self.gene_children.delete 0
    self.gene_children = @[handle_assignment_shortcuts(self.gene_children)]
    self.gene_children.insert self.gene_type, 0
    self.gene_type = first
    return true

Normalizers.add proc(self: Value): bool =
  if self.gene_children.len < 1:
    return false
  var `type` = self.gene_type
  var first = self.gene_children[0]
  if first.kind == VkSymbol:
    if first.symbol == ".":
      self.gene_props[SELF_KEY] = `type`
      self.gene_children.delete 0
      self.gene_props[METHOD_KEY] = self.gene_children[0]
      self.gene_children.delete 0
      self.gene_type = new_gene_symbol("$invoke_dynamic")
      return true
    elif first.symbol[0] == '.' and first.symbol != "...":
      self.gene_props[SELF_KEY] = `type`
      self.gene_props[METHOD_KEY] = new_gene_string_move(first.symbol.substr(1))
      self.gene_children.delete 0
      self.gene_type = new_gene_symbol("$invoke_method")
      return true

Normalizers.add proc(self: Value): bool =
  if self.gene_children.len < 1:
    return false
  var first = self.gene_children[0]
  if first.kind == VkSymbol and first.symbol == "->":
    self.gene_props[ARGS_KEY] = self.gene_type
    self.gene_type = self.gene_children[0]
    self.gene_children.delete 0
    return true

# # Normalize symbols like "a..." etc
# # @Return: a normalized value to replace the original value
# proc normalize_symbol(self: Value): Value =
#   todo()

# # Normalize self.vec, self.gene_children, self.map, self.gene_props etc but don't go further
# proc normalize_children*(self:  Value) =
#   todo()

proc normalize*(self:  Value) =
  if self.gene_type == Quote:
    return
  for n in Normalizers:
    if n(self):
      break

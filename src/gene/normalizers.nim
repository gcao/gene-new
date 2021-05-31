import strutils, tables

import ./map_key
import ./types

const BINARY_OPS* = [
  "+", "-", "*", "/", "**",
  "=", "+=", "-=", "*=", "/=", "**=",
  "==", "!=", "<", "<=", ">", ">=",
  "&&", "||", # TODO: xor
  "&&=", "||=",
  "&",  "|",  # TODO: xor for bit operation
  "&=", "|=",
]

type
  Normalizer* = proc(self: Value): bool

var Normalizers: seq[Normalizer]

# Important: order of normalizers matters. normalize() should be tested as a whole

Normalizers.add proc(self: Value): bool =
  var `type` = self.gene_type
  if `type`.kind == VkSymbol:
    if `type`.symbol[0] == '.' and `type`.symbol != "...":  # (.method x y z)
      self.gene_props[SELF_KEY] = new_gene_symbol("self")
      self.gene_props[METHOD_KEY] = new_gene_string_move(`type`.symbol.substr(1))
      self.gene_type = new_gene_symbol("$invoke_method")

# Normalizers.add proc(self: Value): bool =
#   var `type` = self.gene_type
#   if `type`.kind == VkSymbol:
#     if `type`.symbol == "import" or `type`.symbol == "import_native":
#       var names: seq[Value] = @[]
#       var module: Value
#       var expect_module = false
#       for val in self.gene_data:
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
#       self.gene_data.insert(new_gene_symbol("_"), 0)
#       return true
#     elif self.gene_type.symbol == "fnxx":
#       self.gene_type = new_gene_symbol("fn")
#       self.gene_data.insert(new_gene_symbol("_"), 0)
#       self.gene_data.insert(new_gene_symbol("_"), 0)
#       return true

Normalizers.add proc(self: Value): bool =
  if self.gene_data.len < 1:
    return false
  var `type` = self.gene_type
  var first = self.gene_data[0]
  if first.kind == VkSymbol:
    if first.symbol == "=" and `type`.kind == VkSymbol and `type`.symbol.startsWith("@"):
      # (@prop = val)
      self.gene_type = new_gene_symbol("$set")
      self.gene_data[0] = `type`
      self.gene_data.insert(new_gene_symbol("self"), 0)
      return true

Normalizers.add proc(self: Value): bool =
  if self.gene_data.len < 1:
    return false
  var first = self.gene_data[0]
  if first.kind != VkSymbol or first.symbol notin BINARY_OPS:
    return false

  self.gene_data.delete 0
  self.gene_data.insert self.gene_type, 0
  self.gene_type = first
  return true

Normalizers.add proc(self: Value): bool =
  if self.gene_data.len < 1:
    return false
  var `type` = self.gene_type
  var first = self.gene_data[0]
  if first.kind == VkSymbol and first.symbol[0] == '.' and first.symbol != "...":
    self.gene_props[SELF_KEY] = `type`
    self.gene_props[METHOD_KEY] = new_gene_string_move(first.symbol.substr(1))
    self.gene_data.delete 0
    self.gene_type = new_gene_symbol("$invoke_method")
    return true

Normalizers.add proc(self: Value): bool =
  if self.gene_data.len < 1:
    return false
  var first = self.gene_data[0]
  if first.kind == VkSymbol and first.symbol == "->":
    self.gene_props[ARGS_KEY] = self.gene_type
    self.gene_type = self.gene_data[0]
    self.gene_data.delete 0
    return true

# # Normalize symbols like "a..." etc
# # @Return: a normalized value to replace the original value
# proc normalize_symbol(self: Value): Value =
#   todo()

# # Normalize self.vec, self.gene_data, self.map, self.gene_props etc but don't go further
# proc normalize_children*(self:  Value) =
#   todo()

proc normalize*(self:  Value) =
  if self.gene_type == Quote:
    return
  for n in Normalizers:
    if n(self):
      break

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

  IfState = enum
    IsIf, IsIfCond, IsIfLogic,
    IsElif, IsElifCond, IsElifLogic,
    IsIfNot, IsElifNot,
    IsElse,

var Normalizers: seq[Normalizer]

# Important: order of normalizers matters. normalize() should be tested as a whole

Normalizers.add proc(self: Value): bool =
  var `type` = self.gene_type
  if `type`.kind == VkSymbol:
    if `type`.symbol[0] == '.' and `type`.symbol != "...":  # (.method x y z)
      self.gene_props[SELF_KEY] = new_gene_symbol("self")
      self.gene_props[METHOD_KEY] = new_gene_string_move(`type`.symbol.substr(1))
      self.gene_type = new_gene_symbol("$invoke_method")

Normalizers.add proc(self: Value): bool =
  var `type` = self.gene_type
  if `type` == If:
    # Store if/elif/else block
    var logic: seq[Value]
    var elifs: seq[Value]

    var state = IsIf
    proc handler(input: Value) =
      case state:
      of IsIf:
        if input == nil:
          not_allowed()
        elif input == Not:
          state = IsIfNot
        else:
          self.gene_props[COND_KEY] = input
          state = IsIfCond
      of IsIfNot:
        self.gene_props[COND_KEY] = new_gene_gene(Not, input)
        state = IsIfCond
      of IsIfCond:
        state = IsIfLogic
        logic = @[]
        if input == nil:
          not_allowed()
        elif input != Then:
          logic.add(input)
      of IsIfLogic:
        if input == nil:
          self.gene_props[THEN_KEY] = logic
        elif input == Elif:
          self.gene_props[THEN_KEY] = logic
          state = IsElif
        elif input == Else:
          self.gene_props[THEN_KEY] = logic
          state = IsElse
          logic = @[]
        else:
          logic.add(input)
      of IsElif:
        if input == nil:
          not_allowed()
        elif input == Not:
          state = IsElifNot
        else:
          elifs.add(input)
          state = IsElifCond
      of IsElifNot:
        elifs.add(new_gene_gene(Not, input))
        state = IsElifCond
      of IsElifCond:
        state = IsElifLogic
        logic = @[]
        if input == nil:
          not_allowed()
        elif input != Then:
          logic.add(input)
      of IsElifLogic:
        if input == nil:
          elifs.add(new_gene_vec(logic))
          self.gene_props[ELIF_KEY] = elifs
        elif input == Elif:
          elifs.add(new_gene_vec(logic))
          self.gene_props[ELIF_KEY] = elifs
          state = IsElif
        elif input == Else:
          elifs.add(new_gene_vec(logic))
          self.gene_props[ELIF_KEY] = elifs
          state = IsElse
          logic = @[]
        else:
          logic.add(input)
      of IsElse:
        if input == nil:
          self.gene_props[ELSE_KEY] = logic
        else:
          logic.add(input)

    for item in self.gene_data:
      handler(item)
    handler(nil)

    # Add empty blocks when they are missing
    if not self.gene_props.has_key(THEN_KEY):
      self.gene_props[THEN_KEY] = @[]
    if not self.gene_props.has_key(ELSE_KEY):
      self.gene_props[ELSE_KEY] = @[]

    self.gene_data.reset  # Clear our gene_data as it's not needed any more

Normalizers.add proc(self: Value): bool =
  var `type` = self.gene_type
  if `type`.kind == VkSymbol:
    if `type`.symbol == "import" or `type`.symbol == "import_native":
      var names: seq[Value] = @[]
      var module: Value
      var expect_module = false
      for val in self.gene_data:
        if expect_module:
          module = val
        elif val.kind == VkSymbol and val.symbol == "from":
          expect_module = true
        else:
          names.add(val)
      self.gene_props[NAMES_KEY] = new_gene_vec(names)
      self.gene_props[MODULE_KEY] = module
      return true

Normalizers.add proc(self: Value): bool =
  if self.gene_type.kind == VkSymbol:
    if self.gene_type.symbol == "fnx":
      self.gene_type = new_gene_symbol("fn")
      self.gene_data.insert(new_gene_symbol("_"), 0)
      return true
    elif self.gene_type.symbol == "fnxx":
      self.gene_type = new_gene_symbol("fn")
      self.gene_data.insert(new_gene_symbol("_"), 0)
      self.gene_data.insert(new_gene_symbol("_"), 0)
      return true

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

# Normalize self.vec, self.gene_data, self.map, self.gene_props etc but don't go further
proc normalize_children*(self:  Value) =
  todo()

proc normalize*(self:  Value) =
  if self.gene_type == Quote:
    return
  for n in Normalizers:
    if n(self):
      break

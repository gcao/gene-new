import strutils, tables

import ./map_key
import ./types

type
  Normalizer* = proc(self: GeneValue): bool

  IfState = enum
    IsIf, IsIfCond, IsIfLogic,
    IsElif, IsElifCond, IsElifLogic,
    IsIfNot, IsElifNot,
    IsElse,

var Normalizers: seq[Normalizer]

# Important: order of normalizers matters. normalize() should be tested as a whole

Normalizers.add proc(self: GeneValue): bool =
  var `type` = self.gene.type
  if `type`.kind == GeneSymbol:
    if `type`.symbol.startsWith(".@"):
      var new_type = new_gene_symbol("@")
      var new_gene = new_gene_gene(new_type)
      new_gene.gene.normalized = true
      if `type`.symbol.len > 2:
        var name = `type`.symbol.substr(2).to_selector_matcher()
        new_gene.gene.data.insert(name, 0)
      else:
        for item in self.gene.data:
          new_gene.gene.data.add(item)
      self.gene.type = new_gene
      self.gene.data = @[new_gene_symbol("self")]
      return true
    elif `type`.symbol[0] == '.' and `type`.symbol != "...":  # (.method x y z)
      self.gene.props[SELF_KEY] = new_gene_symbol("self")
      self.gene.props[METHOD_KEY] = new_gene_string_move(`type`.symbol.substr(1))
      self.gene.type = new_gene_symbol("$invoke_method")
  elif `type`.kind == GeneComplexSymbol and `type`.csymbol.first.startsWith(".@"):
    var new_type = new_gene_symbol("@")
    var new_gene = new_gene_gene(new_type)
    new_gene.gene.normalized = true
    var name = `type`.csymbol.first.substr(2).to_selector_matcher()
    new_gene.gene.data.insert(name, 0)
    for part in `type`.csymbol.rest:
      new_gene.gene.data.add(part.to_selector_matcher())
    self.gene.type = new_gene
    self.gene.data = @[new_gene_symbol("self")]
    return true

Normalizers.add proc(self: GeneValue): bool =
  var `type` = self.gene.type
  if `type` == If:
    # Store if/elif/else block
    var logic: seq[GeneValue]
    var elifs: seq[GeneValue]

    var state = IsIf
    proc handler(input: GeneValue) =
      case state:
      of IsIf:
        if input == nil:
          not_allowed()
        elif input == Not:
          state = IsIfNot
        else:
          self.gene.props[COND_KEY] = input
          state = IsIfCond
      of IsIfNot:
        self.gene.props[COND_KEY] = new_gene_gene(Not, input)
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
          self.gene.props[THEN_KEY] = logic
        elif input == Elif:
          self.gene.props[THEN_KEY] = logic
          state = IsElif
        elif input == Else:
          self.gene.props[THEN_KEY] = logic
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
          self.gene.props[ELIF_KEY] = elifs
        elif input == Elif:
          elifs.add(new_gene_vec(logic))
          self.gene.props[ELIF_KEY] = elifs
          state = IsElif
        elif input == Else:
          elifs.add(new_gene_vec(logic))
          self.gene.props[ELIF_KEY] = elifs
          state = IsElse
          logic = @[]
        else:
          logic.add(input)
      of IsElse:
        if input == nil:
          self.gene.props[ELSE_KEY] = logic
        else:
          logic.add(input)

    for item in self.gene.data:
      handler(item)
    handler(nil)

    # Add empty blocks when they are missing
    if not self.gene.props.has_key(THEN_KEY):
      self.gene.props[THEN_KEY] = @[]
    if not self.gene.props.has_key(ELSE_KEY):
      self.gene.props[ELSE_KEY] = @[]

    self.gene.data.reset  # Clear our gene.data as it's not needed any more

Normalizers.add proc(self: GeneValue): bool =
  var `type` = self.gene.type
  if `type`.kind == GeneSymbol:
    if `type`.symbol == "import" or `type`.symbol == "import_native":
      var names: seq[GeneValue] = @[]
      var module: GeneValue
      var expect_module = false
      for val in self.gene.data:
        if expect_module:
          module = val
        elif val.kind == GeneSymbol and val.symbol == "from":
          expect_module = true
        else:
          names.add(val)
      self.gene.props[NAMES_KEY] = new_gene_vec(names)
      self.gene.props[MODULE_KEY] = module
      return true

Normalizers.add proc(self: GeneValue): bool =
  if self.gene.type.kind == GeneSymbol:
    if self.gene.type.symbol == "fnx":
      self.gene.type = new_gene_symbol("fn")
      self.gene.data.insert(new_gene_symbol("_"), 0)
      return true
    elif self.gene.type.symbol == "fnxx":
      self.gene.type = new_gene_symbol("fn")
      self.gene.data.insert(new_gene_symbol("_"), 0)
      self.gene.data.insert(new_gene_symbol("_"), 0)
      return true

Normalizers.add proc(self: GeneValue): bool =
  if self.gene.data.len < 1:
    return false
  var `type` = self.gene.type
  var first = self.gene.data[0]
  if first.kind == GeneSymbol:
    if first.symbol == "=" and `type`.kind == GeneSymbol and `type`.symbol.startsWith("@"):
      # (@prop = val)
      self.gene.type = new_gene_symbol("$set")
      self.gene.data[0] = `type`
      self.gene.data.insert(new_gene_symbol("self"), 0)
      return true

Normalizers.add proc(self: GeneValue): bool =
  if self.gene.data.len < 1:
    return false
  var first = self.gene.data[0]
  if first.kind != GeneSymbol or first.symbol notin BINARY_OPS:
    return false

  self.gene.data.delete 0
  self.gene.data.insert self.gene.type, 0
  self.gene.type = first
  return true

Normalizers.add proc(self: GeneValue): bool =
  if self.gene.data.len < 1:
    return false
  var `type` = self.gene.type
  var first = self.gene.data[0]
  if first.kind == GeneSymbol and first.symbol.startsWith(".@"):
    var new_type = new_gene_symbol("@")
    var new_gene = new_gene_gene(new_type)
    new_gene.gene.normalized = true
    if first.symbol.len == 2:
      for i in 1..<self.gene.data.len:
        new_gene.gene.data.add(self.gene.data[i])
    else:
      new_gene.gene.data.add(first.symbol.substr(2).to_selector_matcher())
    self.gene.data = @[`type`]
    self.gene.type = new_gene
    return true
  elif first.kind == GeneComplexSymbol and first.csymbol.first.startsWith(".@"):
    var new_type = new_gene_symbol("@")
    var new_gene = new_gene_gene(new_type)
    new_gene.gene.normalized = true
    var name = first.csymbol.first.substr(2).to_selector_matcher()
    new_gene.gene.data.add(name)
    for part in first.csymbol.rest:
      new_gene.gene.data.add(part.to_selector_matcher())
    self.gene.data = @[`type`]
    self.gene.type = new_gene
    return true

Normalizers.add proc(self: GeneValue): bool =
  if self.gene.data.len < 1:
    return false
  var `type` = self.gene.type
  var first = self.gene.data[0]
  if first.kind == GeneSymbol and first.symbol[0] == '.' and first.symbol != "...":
    self.gene.props[SELF_KEY] = `type`
    self.gene.props[METHOD_KEY] = new_gene_string_move(first.symbol.substr(1))
    self.gene.data.delete 0
    self.gene.type = new_gene_symbol("$invoke_method")
    return true

Normalizers.add proc(self: GeneValue): bool =
  if self.gene.data.len < 1:
    return false
  var first = self.gene.data[0]
  if first.kind == GeneSymbol and first.symbol == "->":
    self.gene.props[ARGS_KEY] = self.gene.type
    self.gene.type = self.gene.data[0]
    self.gene.data.delete 0
    return true

# # Normalize symbols like "a..." etc
# # @Return: a normalized value to replace the original value
# proc normalize_symbol(self: GeneValue): GeneValue =
#   todo()

# Normalize self.vec, self.gene.data, self.map, self.gene.props etc but don't go further
proc normalize_children*(self:  GeneValue) =
  todo()

proc normalize*(self:  GeneValue) =
  if self.kind != GeneGene or self.gene.normalized:
    return
  if self.gene.type == Quote:
    return
  for n in Normalizers:
    if n(self):
      break
  self.gene.normalized = true

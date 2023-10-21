import tables

import ../types

const COND_KEY* = "cond"
const THEN_KEY* = "then"
const ELIF_KEY* = "elif"
const ELSE_KEY* = "else"

type
  IfState = enum
    IsIf, IsIfCond, IsIfLogic,
    IsElif, IsElifCond, IsElifLogic,
    IsIfNot, IsElifNot,
    IsElse,

proc normalize_if*(self: Value) =
  # TODO: return a tuple to be used by the translator
  if self.gene_props.has_key("cond"):
    return
  var `type` = self.gene_type
  if `type`.is_symbol("if"):
    # Store if/elif/else block
    var logic: seq[Value]
    var elifs: seq[Value]

    var state = IsIf
    proc handler(input: Value) =
      case state:
      of IsIf:
        if input == nil:
          not_allowed()
        elif input.is_symbol("not"):
          state = IsIfNot
        else:
          self.gene_props["cond"] = input
          state = IsIfCond
      of IsIfNot:
        self.gene_props["cond"] = new_gene_gene(new_gene_symbol("not"), input)
        state = IsIfCond
      of IsIfCond:
        state = IsIfLogic
        logic = @[]
        if input == nil:
          not_allowed()
        elif not input.is_symbol("then"):
          logic.add(input)
      of IsIfLogic:
        if input == nil:
          self.gene_props["then"] = new_gene_stream(logic)
        elif input.is_symbol("elif"):
          self.gene_props["then"] = new_gene_stream(logic)
          state = IsElif
        elif input.is_symbol("else"):
          self.gene_props["then"] = new_gene_stream(logic)
          state = IsElse
          logic = @[]
        else:
          logic.add(input)
      of IsElif:
        if input == nil:
          not_allowed()
        elif input.is_symbol("not"):
          state = IsElifNot
        else:
          elifs.add(input)
          state = IsElifCond
      of IsElifNot:
        elifs.add(new_gene_gene(new_gene_symbol("not"), input))
        state = IsElifCond
      of IsElifCond:
        state = IsElifLogic
        logic = @[]
        if input == nil:
          not_allowed()
        elif not input.is_symbol("then"):
          logic.add(input)
      of IsElifLogic:
        if input == nil:
          elifs.add(new_gene_stream(logic))
          self.gene_props["elif"] = elifs
        elif input.is_symbol("elif"):
          elifs.add(new_gene_stream(logic))
          self.gene_props["elif"] = elifs
          state = IsElif
        elif input.is_symbol("else"):
          elifs.add(new_gene_stream(logic))
          self.gene_props["elif"] = elifs
          state = IsElse
          logic = @[]
        else:
          logic.add(input)
      of IsElse:
        if input == nil:
          self.gene_props["else"] = new_gene_stream(logic)
        else:
          logic.add(input)

    for item in self.gene_children:
      handler(item)
    handler(nil)

    # Add empty blocks when they are missing
    if not self.gene_props.has_key("then"):
      self.gene_props["then"] = new_gene_stream(@[])
    if not self.gene_props.has_key("else"):
      self.gene_props["else"] = new_gene_stream(@[])

    self.gene_children.reset  # Clear our gene_children as it's not needed any more

import tables

import ../map_key
import ../types
import ../translators
import ../interpreter

type
  ExIf* = ref object of Expr
    cond*: Expr
    then*: Expr
    elifs*: seq[(Expr, Expr)]
    `else`*: Expr

  IfState = enum
    IsIf, IsIfCond, IsIfLogic,
    IsElif, IsElifCond, IsElifLogic,
    IsIfNot, IsElifNot,
    IsElse,

let COND_KEY* = add_key("cond")
let THEN_KEY* = add_key("then")
let ELIF_KEY* = add_key("elif")
let ELSE_KEY* = add_key("else")

proc normalize_if(self: Value) =
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
          self.gene_props[THEN_KEY] = new_gene_stream(logic)
        elif input == Elif:
          self.gene_props[THEN_KEY] = new_gene_stream(logic)
          state = IsElif
        elif input == Else:
          self.gene_props[THEN_KEY] = new_gene_stream(logic)
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
          elifs.add(new_gene_stream(logic))
          self.gene_props[ELIF_KEY] = elifs
        elif input == Elif:
          elifs.add(new_gene_stream(logic))
          self.gene_props[ELIF_KEY] = elifs
          state = IsElif
        elif input == Else:
          elifs.add(new_gene_stream(logic))
          self.gene_props[ELIF_KEY] = elifs
          state = IsElse
          logic = @[]
        else:
          logic.add(input)
      of IsElse:
        if input == nil:
          self.gene_props[ELSE_KEY] = new_gene_stream(logic)
        else:
          logic.add(input)

    for item in self.gene_data:
      handler(item)
    handler(nil)

    # Add empty blocks when they are missing
    if not self.gene_props.has_key(THEN_KEY):
      self.gene_props[THEN_KEY] = new_gene_stream(@[])
    if not self.gene_props.has_key(ELSE_KEY):
      self.gene_props[ELSE_KEY] = new_gene_stream(@[])

    self.gene_data.reset  # Clear our gene_data as it's not needed any more

proc eval_if(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExIf](expr)
  var v = self.eval(frame, expr.cond)
  if v:
    result = self.eval(frame, expr.`then`)
  elif expr.elifs.len > 0:
    for pair in expr.elifs.mitems:
      if self.eval(frame, pair[0]):
        return self.eval(frame, pair[1])
  elif expr.`else` != nil:
    result = self.eval(frame, expr.`else`)

proc init*() =
  GeneTranslators["if"] = proc(value: Value): Expr =
    normalize_if(value)
    var r = ExIf(
      evaluator: eval_if,
    )
    r.cond = translate(value.gene_props[COND_KEY])
    r.then = translate(value.gene_props[THEN_KEY])
    if value.gene_props.has_key(ELIF_KEY):
      var elifs = value.gene_props[ELIF_KEY]
      var i = 0
      while i < elifs.vec.len:
        var cond = translate(elifs.vec[i])
        var logic = translate(elifs.vec[i + 1])
        r.elifs.add((cond, logic))
        i += 2
    r.`else` = translate(value.gene_props[ELSE_KEY])
    result = r

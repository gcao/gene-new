import tables

import ../types
import ../interpreter_base

type
  ExIf* = ref object of Expr
    cond*: Expr
    then*: Expr
    elifs*: seq[(Expr, Expr)]
    `else`*: Expr

  ExNot* = ref object of Expr
    cond*: Expr

  ExBool* = ref object of Expr
    data*: Expr

  IfState = enum
    IsIf, IsIfCond, IsIfLogic,
    IsElif, IsElifCond, IsElifLogic,
    IsIfNot, IsElifNot,
    IsElse,

proc normalize_if(self: Value) =
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

proc eval_if(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExIf](expr)
  if self.eval(frame, expr.cond):
    return self.eval(frame, expr.`then`)
  if expr.elifs.len > 0:
    for pair in expr.elifs.mitems:
      if self.eval(frame, pair[0]):
        return self.eval(frame, pair[1])
  if expr.`else` != nil:
    return self.eval(frame, expr.`else`)

proc translate_if(value: Value): Expr {.gcsafe.} =
  normalize_if(value)
  var r = ExIf(
    evaluator: eval_if,
  )
  r.cond = translate(value.gene_props["cond"])
  r.then = translate(value.gene_props["then"])
  if value.gene_props.has_key("elif"):
    var elifs = value.gene_props["elif"]
    var i = 0
    while i < elifs.vec.len:
      var cond = translate(elifs.vec[i])
      var logic = translate(elifs.vec[i + 1])
      r.elifs.add((cond, logic))
      i += 2
  r.`else` = translate(value.gene_props["else"])
  result = r

proc eval_not(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  not self.eval(frame, cast[ExNot](expr).cond).to_bool

proc translate_not(value: Value): Expr {.gcsafe.} =
  ExNot(
    evaluator: eval_not,
    cond: translate(value.gene_children[0]),
  )

proc eval_bool(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  self.eval(frame, cast[ExBool](expr).data).to_bool

proc translate_bool(value: Value): Expr {.gcsafe.} =
  ExBool(
    evaluator: eval_bool,
    data: translate(value.gene_children[0]),
  )

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    VM.gene_translators["if"] = translate_if
    VM.gene_translators["not"] = translate_not
    VM.gene_translators["!"] = translate_not
    VM.gene_translators["!!"] = translate_bool

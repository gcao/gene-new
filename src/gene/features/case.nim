import tables, nre

import ../types
import ../interpreter_base

type
  CaseState = enum
    CsInput, CsWhen, CsWhenLogic, CsElse

  ExCase* = ref object of Expr
    case_input*: Expr
    case_blks*: seq[Expr]   # Code blocks
    case_else*: Expr        # Else block
    case_lite_mapping*: Table[string, int]  # literal -> block index
    case_more_mapping*: seq[(Expr, int)]    # non-literal -> block index

proc case_equals(input: Value, pattern: Value): bool =
  case input.kind:
  of VkInt:
    case pattern.kind:
    of VkInt:
      result = input.int == pattern.int
    of VkRange:
      result = input.int >= pattern.range.start.int and input.int < pattern.range.end.int
    of VkClass:
      result = input.is_a(pattern.class)
    else:
      discard
      # not_allowed("case_equals: int vs " & $pattern.kind)
  of VkString:
    case pattern.kind:
    of VkString:
      result = input.str == pattern.str
    of VkRegex:
      result = input.str.match(pattern.regex).is_some()
    of VkClass:
      result = input.is_a(pattern.class)
    else:
      discard
      # not_allowed("case_equals: string vs " & $pattern.kind)
  else:
    if pattern.kind == VkClass:
      result = input.is_a(pattern.class)
    else:
      result = input == pattern

proc eval_case(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExCase](expr)
  var input = self.eval(frame, expr.case_input)
  for pair in expr.case_more_mapping.mitems:
    var pattern = self.eval(frame, pair[0])
    if input.case_equals(pattern):
      return self.eval(frame, expr.case_blks[pair[1]])
  result = self.eval(frame, expr.case_else)

proc translate_case(node: Value): Expr {.gcsafe.} =
  # Create a variable because result can not be accessed from closure.
  var expr = ExCase(
    evaluator: eval_case,
  )
  expr.case_input = translate(node.gene_children[0])

  var state = CsInput
  var cond: Value
  var logic: seq[Value]

  proc update_mapping(cond: Value, logic: seq[Value]) =
    var index = expr.case_blks.len
    expr.case_blks.add(translate(logic))
    if cond.kind == VkVector:
      for item in cond.vec:
        expr.case_more_mapping.add((translate(item), index))
    else:
      expr.case_more_mapping.add((translate(cond), index))

  proc handler(input: Value) =
    case state:
    of CsInput:
      if input.is_symbol("when"):
        state = CsWhen
      else:
        not_allowed()
    of CsWhen:
      state = CsWhenLogic
      cond = input
      logic = @[]
    of CsWhenLogic:
      if input == nil:
        update_mapping(cond, logic)
      elif input.is_symbol("when"):
        state = CsWhen
        update_mapping(cond, logic)
      elif input.is_symbol("else"):
        state = CsElse
        update_mapping(cond, logic)
        logic = @[]
      else:
        logic.add(input)
    of CsElse:
      if input == nil:
        expr.case_else = translate(logic)
      else:
        logic.add(input)

  var i = 1
  while i < node.gene_children.len:
    handler(node.gene_children[i])
    i += 1
  handler(nil)

  result = expr

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    VM.gene_translators["case"] = translate_case

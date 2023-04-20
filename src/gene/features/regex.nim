import nre, tables

import ../types
import ../interpreter_base

const REGEX_OPS* = ["=~", "!~"]

type
  ExMatch* = ref object of Expr
    input*: Expr
    pattern*: Expr

  ExRegex* = ref object of Expr
    flags: set[RegexFlag]
    data*: seq[Expr]

proc eval_match(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var expr = cast[ExMatch](expr)
  var input = self.eval(frame, expr.input)
  var pattern = self.eval(frame, expr.pattern)
  var r = input.str.match(pattern.regex)
  if r.is_some():
    var m = r.get()
    result = Value(kind: VkRegexMatch, regex_match: m)
    frame.scope.def_member("$~", result)
    var i = 0
    for item in m.captures.to_seq:
      var name = "$~" & $i
      var value = Value(kind: VkNil)
      if item.is_some():
        value = item.get()
      frame.scope.def_member(name, value)
      i += 1
  else:
    return Value(kind: VkNil)

proc eval_not_match(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var expr = cast[ExMatch](expr)
  var input = self.eval(frame, expr.input)
  var pattern = self.eval(frame, expr.pattern)
  var m = input.str.match(pattern.regex)
  return m.is_none()

proc translate_match*(value: Value): Expr {.gcsafe.} =
  var evaluator: Evaluator
  case value.gene_children[0].str:
  of "=~":
    evaluator = eval_match
  of "!~":
    evaluator = eval_not_match
  else:
    not_allowed("translate_match " & $value.gene_children[0].str)

  ExMatch(
    evaluator: evaluator,
    input: translate(value.gene_type),
    pattern: translate(value.gene_children[1]),
  )

proc eval_regex(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var expr = cast[ExRegex](expr)
  var s = ""
  for e in expr.data.mitems:
    s &= self.eval(frame, e).to_s
  result = new_gene_regex(s, expr.flags)

proc translate_regex*(value: Value): Expr {.gcsafe.} =
  var r = ExRegex(
    evaluator: eval_regex,
  )
  if value.gene_props.has_key("i"):
    r.flags.incl(RfIgnoreCase)
  if value.gene_props.has_key("m"):
    r.flags.incl(RfMultiLine)
  for item in value.gene_children:
    r.data.add(translate(item))
  return r

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    VM.gene_translators["$regex"] = translate_regex
    # Handled in src/gene/features/gene.nim
    # VM.gene_translators["=~"] = translate_match
    # VM.gene_translators["!~"] = translate_match

import nre, tables

import ../map_key
import ../types
import ../translators

const REGEX_OPS* = ["=~", "!~"]

type
  ExMatch* = ref object of Expr
    input*: Expr
    pattern*: Expr

  ExRegex* = ref object of Expr
    flags: set[RegexFlag]
    data*: seq[Expr]

proc eval_match(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExMatch](expr)
  var input = self.eval(frame, expr.input)
  var pattern = self.eval(frame, expr.pattern)
  var r = input.str.match(pattern.regex)
  if r.is_some():
    var m = r.get()
    result = Value(kind: VkRegexMatch, regex_match: m)
    frame.scope.def_member("$~".to_key, result)
    var i = 0
    for item in m.captures.to_seq:
      var name = "$~" & $i
      var value = Nil
      if item.is_some():
        value = item.get()
      frame.scope.def_member(name.to_key, value)
      i += 1
  else:
    return Nil

proc eval_not_match(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExMatch](expr)
  var input = self.eval(frame, expr.input)
  var pattern = self.eval(frame, expr.pattern)
  var m = input.str.match(pattern.regex)
  return m.is_none()

proc translate_match*(value: Value): Expr =
  var evaluator: Evaluator
  case value.gene_children[0].symbol:
  of "=~":
    evaluator = eval_match
  of "!~":
    evaluator = eval_not_match
  else:
    not_allowed("translate_match " & $value.gene_children[0].symbol)

  ExMatch(
    evaluator: evaluator,
    input: translate(value.gene_type),
    pattern: translate(value.gene_children[1]),
  )

proc eval_regex(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExRegex](expr)
  var s = ""
  for e in expr.data.mitems:
    s &= self.eval(frame, e).to_s
  result = new_gene_regex(s, expr.flags)

proc translate_regex*(value: Value): Expr =
  var r = ExRegex(
    evaluator: eval_regex,
  )
  if value.gene_props.has_key("i".to_key):
    r.flags.incl(RfIgnoreCase)
  if value.gene_props.has_key("m".to_key):
    r.flags.incl(RfMultiLine)
  for item in value.gene_children:
    r.data.add(translate(item))
  return r

proc init*() =
  GeneTranslators["$regex"] = translate_regex
  # Handled in src/gene/features/gene.nim
  # GeneTranslators["=~"] = translate_match
  # GeneTranslators["!~"] = translate_match

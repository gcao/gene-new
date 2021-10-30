import nre

import ../types
import ../translators

const REGEX_OPS* = ["=~", "!~"]

type
  ExMatch* = ref object of Expr
    input*: Expr
    pattern*: Expr

proc eval_match(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExMatch](expr)
  var input = self.eval(frame, expr.input)
  var pattern = self.eval(frame, expr.pattern)
  var m = input.str.match(pattern.regex)
  if m.is_some():
    # TODO: return match object
    return True
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
  case value.gene_data[0].symbol:
  of "=~":
    evaluator = eval_match
  of "!~":
    evaluator = eval_not_match
  else:
    not_allowed("translate_match " & $value.gene_data[0].symbol)

  ExMatch(
    evaluator: evaluator,
    input: translate(value.gene_type),
    pattern: translate(value.gene_data[1]),
  )

proc init*() =
  discard
  # GeneTranslators["=~"] = translate_match
  # GeneTranslators["!~"] = translate_match

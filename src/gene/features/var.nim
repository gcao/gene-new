import tables

import ../map_key
import ../types
import ../exprs
import ../translators
import ../interpreter

type
  # SymbolKind* = enum
  #   SkUnknown
  #   SkGene
  #   SkGenex
  #   SkNamespace
  #   SkScope
  ExSymbol* = ref object of Expr
    name*: MapKey
    # kind*: SymbolKind
  ExVar* = ref object of Expr
    name*: MapKey
    value*: Expr

proc eval_symbol(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  frame[cast[ExSymbol](expr).name]
  # var e = cast[ExSymbol](expr)
  # case e.kind:
  # of SkUnknown:
  #   if frame.scope.has_key(e.name):
  #     e.kind = SkScope
  #     result = frame.scope[e.name]
  #   else:
  #     e.kind = SkNamespace
  #     result = frame.ns[e.name]
  # of SkScope:
  #   result = frame.scope[e.name]
  # of SkNamespace:
  #   result = frame.ns[e.name]
  # else:
  #   todo()

proc eval_var(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var value = self.eval(frame, cast[ExVar](expr).value)
  frame.scope.def_member(cast[ExVar](expr).name, value)

proc init*() =
  Translators[VkSymbol] = proc(value: Value): Expr =
    ExSymbol(
      evaluator: eval_symbol,
      name: value.symbol.to_key,
    )

  GeneTranslators["var"] = proc(value: Value): Expr =
    var name = value.gene_data[0]
    var v: Expr
    if value.gene_data.len > 1:
      v = translate(value.gene_data[1])
    else:
      v = new_ex_literal(Nil)
    case name.kind:
    of VkSymbol:
      result = ExVar(
        evaluator: eval_var,
        name: name.symbol.to_key,
        value: v,
      )
    else:
      todo($name.kind)

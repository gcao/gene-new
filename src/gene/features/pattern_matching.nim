import tables

import ../types
import ../interpreter_base

type
  ExMatch* = ref object of Expr
    matcher: RootMatcher
    value*: Expr

proc eval_match(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  var expr = cast[ExMatch](expr)
  var matcher = expr.matcher
  var value = self.eval(frame, expr.value)
  case matcher.hint.mode:
  of MhNone:
    discard
  of MhSimpleData:
    case value.kind:
    of VkVector:
      for i, v in value.vec:
        let field = matcher.children[i]
        if field.is_prop:
          frame.self.instance_props[field.name] = v
        else:
          frame.scope.def_member(field.name, v)
    of VkGene:
      for i, v in value.gene_children:
        let field = matcher.children[i]
        if field.is_prop:
          frame.self.instance_props[field.name] = v
        else:
          frame.scope.def_member(field.name, v)
    else:
      todo("eval_match value.kind = " & $value.kind)
  else:
    self.process_args(frame, matcher, value)

proc translate_match(value: Value): Expr {.gcsafe.} =
  return ExMatch(
    evaluator: eval_match,
    matcher: new_arg_matcher(value.gene_children[0]),
    value: translate(value.gene_children[1]),
  )

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    VM.gene_translators["match"] = translate_match

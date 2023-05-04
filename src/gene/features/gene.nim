import strutils
import tables

import ../types
import ../interpreter_base
import ./core
import ./arithmetic
import ./module
import ./regex
import ./selector
import ./range

type
  ExGene* = ref object of Expr
    `type`*: Expr
    args*: Value        # The unprocessed args
    args_expr*: Expr    # The translated args

const ASSIGNMENT_OPS = [
  "=",
  "+=", "-=", "*=", "/=", "**=",
  "&&=", "||=",
]

proc eval_gene*(frame: Frame, expr: var Expr): Value =
  var expr = cast[ExGene](expr)
  var `type` = eval(frame, expr.`type`)
  case `type`.kind:
  of VkFunction:
    var fn = `type`.fn
    var fn_scope = new_scope()
    fn_scope.set_parent(fn.parent_scope, fn.parent_scope_max)
    var new_frame = Frame(ns: fn.ns, scope: fn_scope)
    new_frame.parent = frame

    var args_expr = new_ex_arg()
    for k, v in expr.args.gene_props:
      args_expr.props[k] = translate(v)
    for v in expr.args.gene_children:
      args_expr.children.add(translate(v))
    args_expr.check_explode()

    handle_args(frame, new_frame, fn.matcher, args_expr)

    return call_fn_skip_args(new_frame, `type`)

  of VkBoundFunction:
    var bound_fn = `type`.bound_fn
    var fn = bound_fn.target.fn
    var fn_scope = new_scope()
    fn_scope.set_parent(fn.parent_scope, fn.parent_scope_max)
    var new_frame = Frame(ns: fn.ns, scope: fn_scope)
    new_frame.parent = frame
    new_frame.self = bound_fn.self

    var args_expr = new_ex_arg()
    for k, v in expr.args.gene_props:
      args_expr.props[k] = translate(v)
    for v in expr.args.gene_children:
      args_expr.children.add(translate(v))
    args_expr.check_explode()

    handle_args(frame, new_frame, fn.matcher, args_expr)

    return call_fn_skip_args(new_frame, bound_fn.target)

  of VkMacro:
    var `macro` = `type`.macro
    var scope = new_scope()
    scope.set_parent(`macro`.parent_scope, `macro`.parent_scope_max)
    var new_frame = Frame(ns: `macro`.ns, scope: scope)
    new_frame.parent = frame

    var args = expr.args
    var match_result = match(new_frame, `macro`.matcher, args)
    case match_result.kind:
    of MatchSuccess:
      discard
    of MatchMissingFields:
      for field in match_result.missing:
        not_allowed("Argument " & field.to_s & " is missing.")
    else:
      todo()

    if `macro`.body_compiled == nil:
      `macro`.body_compiled = translate(`macro`.body)

    try:
      return eval(new_frame, `macro`.body_compiled)
    except Return as r:
      return r.val
    except system.Exception as e:
      if VM.repl_on_error:
        return repl_on_error(frame, e)
      else:
        raise

  of VkBlock:
    var `block` = `type`.block
    var scope = new_scope()
    scope.set_parent(`block`.parent_scope, `block`.parent_scope_max)
    var new_frame = Frame(ns: `block`.ns, scope: scope)
    new_frame.parent = frame
    new_frame.self = `block`.frame.self

    var args_expr = new_ex_arg()
    for k, v in expr.args.gene_props:
      args_expr.props[k] = translate(v)
    for v in expr.args.gene_children:
      args_expr.children.add(translate(v))
    args_expr.check_explode()

    handle_args(frame, new_frame, `block`.matcher, args_expr)

    try:
      return eval(new_frame, `block`.body_compiled)
    except Return as r:
      return r.val
    except system.Exception as e:
      if VM.repl_on_error:
        return repl_on_error(frame, e)
      else:
        raise

  of VkSelector:
    # translator = `type`.selector.translator
    try:
      var selector = `type`.selector
      var e = translate(expr.args.gene_children[0])
      var v = eval(frame, e)
      return selector.search(v)
    except SelectorNoResult:
      todo()
      # var default_expr: Expr
      # for e in expr.gene_props:
      #   if e == "default":
      #     default_expr = e.map_val
      #     break
      # if default_expr != nil:
      #   result = eval(frame, default_expr)
      # else:
      #   raise

  of VkGeneProcessor:
    var translator = `type`.gene_processor.translator
    var args_expr = translator(expr.args)
    return args_expr.evaluator(frame, args_expr)

  of VkNativeFn, VkNativeFn2:
    var args_expr = new_ex_arg()
    for k, v in expr.args.gene_props:
      args_expr.props[k] = translate(v)
    for v in expr.args.gene_children:
      args_expr.children.add(translate(v))
    args_expr.check_explode()
    var e = cast[Expr](args_expr)
    var args = eval_args(frame, e)
    case `type`.kind:
    of VkNativeFn:
      return `type`.native_fn(frame, args)
    of VkNativeFn2:
      return `type`.native_fn2(frame, args)
    else:
      todo("eval_native_fn " & $`type`.kind)

  of VkNativeMethod, VkNativeMethod2:
    var args_expr = translate_arguments(expr.args)
    var args = eval_args(frame, args_expr)
    return `type`.native_method(frame, frame.self, args)

  of VkInstance:
    expr.args_expr = ExInvoke(
      evaluator: eval_invoke,
      self: expr.`type`,
      meth: "call",
      args: expr.args,
    )
    return eval_invoke(frame, expr.args_expr)

  of VkInterception:
    let target = `type`.interception.target
    let advice = `type`.interception.advice
    case target.kind:
    of VkFunction:
      var args_expr = new_ex_arg()
      for k, v in expr.args.gene_props:
        args_expr.props[k] = translate(v)
      for v in expr.args.gene_children:
        args_expr.children.add(translate(v))
      args_expr.check_explode()
      var e = cast[Expr](args_expr)
      var args = eval_args(frame, e)

      var advice_fn = advice.fn
      var advice_fn_scope = new_scope()
      advice_fn_scope.set_parent(advice_fn.parent_scope, advice_fn.parent_scope_max)
      advice_fn_scope.def_member("$args", args)
      var new_frame = Frame(ns: advice_fn.ns, scope: advice_fn_scope)
      new_frame.parent = frame

      process_args(new_frame, advice_fn.matcher, args)
      discard call_fn_skip_args(new_frame, advice)

      var fn = target.fn
      var fn_scope = new_scope()
      fn_scope.set_parent(fn.parent_scope, fn.parent_scope_max)
      new_frame = Frame(ns: fn.ns, scope: fn_scope)
      new_frame.parent = frame

      process_args(new_frame, fn.matcher, args)
      return call_fn_skip_args(new_frame, target)

    else:
      not_allowed("Interception target must be a function: " & $target.kind)

  of VkSymbol, VkPlaceholder, VkNil:
    result = new_gene_gene(`type`)
    var args_expr = cast[ExArguments](translate_arguments(expr.args))
    for k, v in args_expr.props.mpairs:
      result.gene_props[k] = eval(frame, v)
    for v in args_expr.children.mitems:
      var r = eval(frame, v)
      if r.kind == VkExplode:
        for item in r.explode.vec:
          result.gene_children.add(item)
      else:
        result.gene_children.add(r)
    return result

  else:
    todo("eval_gene " & $`type`.kind)

proc default_translator(value: Value): Expr =
  ExGene(
    evaluator: eval_gene,
    `type`: translate(value.gene_type),
    args: value,
  )

proc handle_assignment_shortcuts(self: seq[Value]): Value =
  if self.len mod 2 == 0:
    raise new_gene_exception("Invalid right value for assignment " & $self)
  if self.len == 1:
    return self[0]
  if self[1].kind == VkSymbol and self[1].str in ASSIGNMENT_OPS:
    result = new_gene_gene(self[1])
    result.gene_children.add(self[0])
    result.gene_children.add(handle_assignment_shortcuts(self[2..^1]))
  else:
    raise new_gene_exception("Invalid right value for assignment " & $self)

proc translate_gene(value: Value): Expr {.gcsafe.} =
  var `type` = value.gene_type
  case `type`.kind:
  of VkSymbol:
    case `type`.str:
    of ".":
      value.gene_props["self"] = new_gene_symbol("self")
      value.gene_props["method"] = value.gene_children[0]
      value.gene_children.delete 0
      value.gene_type = new_gene_symbol("$invoke_dynamic")
    of "...":
      discard
    of "import":
      return translate_import(value)
    else:
      if `type`.str.starts_with("."): # (.method x y z)
        value.gene_props["self"] = new_gene_symbol("self")
        value.gene_props["method"] = new_gene_string_move(`type`.str.substr(1))
        value.gene_type = new_gene_symbol("$invoke_method")
  of VkComplexSymbol:
    if `type`.csymbol[0] == ".":
      if `type`.csymbol[1] == "":
        return translate_invoke_selector3(value)
      else:
        return translate_invoke_selector4(value)
  else:
    discard

  if value.gene_children.len >= 1:
    var first = value.gene_children[0]
    case first.kind:
    of VkSymbol:
      case first.str:
      of ".": # (x . method ...) or (x . function ...)
        value.gene_props["self"] = value.gene_type
        value.gene_children.delete 0
        value.gene_props["method"] = value.gene_children[0]
        value.gene_children.delete 0
        value.gene_type = new_gene_symbol("$invoke_dynamic")
      of "==", "!=", "<", "<=", ">", ">=":
        var data = value.gene_children
        data.insert(value.gene_type)
        return translate_comparisons(data)
      of "&&", "||":
        var data = value.gene_children
        data.insert(value.gene_type)
        return translate_logic(data)
      of "=~", "!~":
        return translate_match(value)
      of "+", "-", "*", "/", "**":
        var data = value.gene_children
        data.insert(value.gene_type)
        return translate_arithmetic(data)
      of "+=", "-=", "*=", "/=", "**=", "&&=", "||=":
        value.gene_children.delete 0
        value.gene_children = @[handle_assignment_shortcuts(value.gene_children)]
        value.gene_children.insert value.gene_type, 0
        value.gene_type = first
      of "..":
        return new_ex_range(translate(`type`), translate(value.gene_children[1]))
      of "=":
        value.gene_children.delete 0
        value.gene_children = @[handle_assignment_shortcuts(value.gene_children)]
        value.gene_children.insert value.gene_type, 0
        value.gene_type = first
      of "->":
        value.gene_props["args"] = value.gene_type
        value.gene_type = value.gene_children[0]
        value.gene_children.delete 0
      else:
        if first.str.startsWith("."):
          value.gene_props["self"] = `type`
          value.gene_props["method"] = new_gene_string_move(first.str.substr(1))
          value.gene_children.delete 0
          value.gene_type = new_gene_symbol("$invoke_method")
    of VkComplexSymbol:
      if first.csymbol[0] == ".":
        if first.csymbol[1] == "":
          return translate_invoke_selector(value)
        else:
          return translate_invoke_selector2(value)
    else:
      discard

  case value.gene_type.kind:
  of VkSymbol:
    var translator = VM.gene_translators.get_or_default(value.gene_type.str, default_translator)
    return translator(value)
  of VkString:
    return translate_string(value)
  of VkFunction:
    # TODO: this can be optimized further
    return ExGene(
      evaluator: eval_gene,
      `type`: new_ex_literal(value.gene_type),
      args: value,
    )
  else:
    return default_translator(value)

proc init*() =
  VmCreatedCallbacks.add proc() =
    VM.translators[VkGene] = translate_gene

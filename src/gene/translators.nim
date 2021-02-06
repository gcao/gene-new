import tables, strutils

import ./map_key
import ./types
import ./normalizers
import ./decorator

const SIMPLE_BINARY_OPS* = [
  "+", "-", "*", "/", "**",
  "==", "!=", "<", "<=", ">", ">=",
  "&&", "||", # TODO: xor
  "&",  "|",  # TODO: xor for bit operation
]

const COMPLEX_BINARY_OPS* = [
  "+=", "-=", "*=", "/=", "**=",
  "&&=", "||=", # TODO: xor
  "&=",  "|=",  # TODO: xor for bit operation
]

type
  Translator* = proc(parent: Expr, val: GeneValue): Expr

  TranslatorManager* = ref object
    mappings*: Table[MapKey, Translator]

  TryParsingState = enum
    TryBody
    TryCatch
    TryCatchBody
    TryFinally

  CaseState = enum
    CsInput, CsWhen, CsWhenLogic, CsElse

var TranslatorMgr* = TranslatorManager()
var CustomTranslators*: seq[Translator]

let TRY*      = new_gene_symbol("try")
let CATCH*    = new_gene_symbol("catch")
let FINALLY*  = new_gene_symbol("finally")

#################### Definitions #################

proc new_expr*(parent: Expr, kind: ExprKind): Expr
proc new_expr*(parent: Expr, node: GeneValue): Expr
proc new_group_expr*(parent: Expr, nodes: seq[GeneValue]): Expr

#################### TranslatorManager ###########

proc `[]`*(self: TranslatorManager, name: MapKey): Translator =
  if self.mappings.has_key(name):
    return self.mappings[name]

proc `[]=`*(self: TranslatorManager, name: MapKey, t: Translator) =
  self.mappings[name] = t

#################### Translators #################

proc add_custom_translator*(t: Translator) =
  CustomTranslators.add(t)

proc new_literal_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(
    kind: ExLiteral,
    parent: parent,
    literal: v,
  )

proc new_symbol_expr*(parent: Expr, s: string): Expr =
  return Expr(
    kind: ExSymbol,
    parent: parent,
    symbol: s.to_key,
  )

proc new_complex_symbol_expr*(parent: Expr, node: GeneValue): Expr =
  return Expr(
    kind: ExComplexSymbol,
    parent: parent,
    csymbol: node.csymbol,
  )

proc new_array_expr*(parent: Expr, v: GeneValue): Expr =
  result = Expr(
    kind: ExArray,
    parent: parent,
    array: @[],
  )
  for item in v.vec:
    result.array.add(new_expr(result, item))

proc new_map_key_expr*(parent: Expr, key: MapKey, val: GeneValue): Expr =
  result = Expr(
    kind: ExMapChild,
    parent: parent,
    map_key: key,
  )
  result.map_val = new_expr(result, val)

proc new_map_expr*(parent: Expr, v: GeneValue): Expr =
  result = Expr(
    kind: ExMap,
    parent: parent,
    map: @[],
  )
  for key, val in v.map:
    var e = new_map_key_expr(result, key, val)
    result.map.add(e)

proc new_gene_expr*(parent: Expr, v: GeneValue): Expr =
  return Expr(
    kind: ExGene,
    parent: parent,
    gene: v,
  )

proc new_range_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExRange,
    parent: parent,
  )
  result.range_start = new_expr(result, val.gene.data[0])
  result.range_end = new_expr(result, val.gene.data[1])
  result.range_incl_start = true
  result.range_incl_end = false

proc new_var_expr*(parent: Expr, node: GeneValue): Expr =
  var name = node.gene.data[0]
  var val = GeneNil
  if node.gene.data.len > 1:
    val = node.gene.data[1]
  result = Expr(
    kind: ExVar,
    parent: parent,
    var_name: name,
  )
  result.var_val = new_expr(result, val)

proc new_assignment_expr*(parent: Expr, node: GeneValue): Expr =
  var name = node.gene.data[0]
  var val = node.gene.data[1]
  result = Expr(
    kind: ExAssignment,
    parent: parent,
    var_name: name,
  )
  result.var_val = new_expr(result, val)

proc new_if_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExIf,
    parent: parent,
  )
  result.if_cond = new_expr(result, val.gene.props[COND_KEY])
  result.if_then = new_group_expr(result, val.gene.props[THEN_KEY].vec)
  if val.gene.props.has_key(ELIF_KEY):
    var elifs = val.gene.props[ELIF_KEY]
    var i = 0
    while i < elifs.vec.len:
      var cond = new_expr(result, elifs.vec[i])
      var logic = new_group_expr(result, elifs.vec[i + 1].vec)
      result.if_elifs.add((cond, logic))
      i += 2
  result.if_else = new_group_expr(result, val.gene.props[ELSE_KEY].vec)

proc new_do_expr*(parent: Expr, node: GeneValue): Expr =
  result = Expr(
    kind: ExDo,
    parent: parent,
  )
  for k, v in node.gene.props:
    result.do_props.add(new_map_key_expr(result, k, v))
  var data = node.gene.data
  data = wrap_with_try(data)
  for item in data:
    result.do_body.add(new_expr(result, item))

proc new_group_expr*(parent: Expr, nodes: seq[GeneValue]): Expr =
  if nodes.len == 1:
    result = new_expr(parent, nodes[0])
  else:
    result = Expr(
      kind: ExGroup,
      parent: parent,
    )
    for node in nodes:
      result.group.add(new_expr(result, node))

proc new_loop_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExLoop,
    parent: parent,
  )
  for node in val.gene.data:
    result.loop_blk.add(new_expr(result, node))

proc new_break_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExBreak,
    parent: parent,
  )
  if val.gene.data.len > 0:
    result.break_val = new_expr(result, val.gene.data[0])

proc new_while_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExWhile,
    parent: parent,
  )
  result.while_cond = new_expr(result, val.gene.data[0])
  for i in 1..<val.gene.data.len:
    var node = val.gene.data[i]
    result.while_blk.add(new_expr(result, node))

proc new_for_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExFor,
    parent: parent,
  )
  result.for_vars = val.gene.data[0]
  result.for_in = new_expr(result, val.gene.data[2])
  for i in 3..<val.gene.data.len:
    var node = val.gene.data[i]
    result.for_blk.add(new_expr(result, node))

proc new_explode_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExExplode,
    parent: parent,
  )
  result.explode = new_expr(parent, val)

proc new_throw_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExThrow,
    parent: parent,
  )
  if val.gene.data.len > 0:
    result.throw_type = new_expr(result, val.gene.data[0])
  if val.gene.data.len > 1:
    result.throw_mesg = new_expr(result, val.gene.data[1])

proc new_try_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExTry,
    parent: parent,
  )
  var state = TryBody
  var catch_exception: Expr
  var catch_body: seq[Expr] = @[]
  for item in val.gene.data:
    case state:
    of TryBody:
      if item == CATCH:
        state = TryCatch
      elif item == FINALLY:
        state = TryFinally
      else:
        result.try_body.add(new_expr(result, item))
    of TryCatch:
      if item == CATCH:
        not_allowed()
      elif item == FINALLY:
        not_allowed()
      else:
        state = TryCatchBody
        catch_exception = new_expr(result, item)
    of TryCatchBody:
      if item == CATCH:
        state = TryCatch
        result.try_catches.add((catch_exception, catch_body))
        catch_exception = nil
        catch_body = @[]
      elif item == FINALLY:
        state = TryFinally
      else:
        catch_body.add(new_expr(result, item))
    of TryFinally:
      result.try_finally.add(new_expr(result, item))
  if state in [TryCatch, TryCatchBody]:
    result.try_catches.add((catch_exception, catch_body))
  elif state == TryFinally:
    if catch_exception != nil:
      result.try_catches.add((catch_exception, catch_body))

# Create expressions for default values
proc update_matchers*(fn: Function, group: seq[Matcher]) =
  for m in group:
    if m.default_value != nil and not m.default_value.is_literal:
      m.default_value_expr = new_expr(fn.expr, m.default_value)
    fn.update_matchers(m.children)

proc new_fn_expr*(parent: Expr, val: GeneValue): Expr =
  var fn: Function = val
  result = Expr(
    kind: ExFn,
    parent: parent,
    fn: fn,
    fn_name: val.gene.data[0],
  )
  fn.expr = result
  fn.update_matchers(fn.matcher.children)

proc new_macro_expr*(parent: Expr, val: GeneValue): Expr =
  var mac: Macro = val
  result = Expr(
    kind: ExMacro,
    parent: parent,
    mac: mac,
    mac_name: val.gene.data[0],
  )
  mac.expr = result

proc new_block_expr*(parent: Expr, val: GeneValue): Expr =
  var blk: Block = val
  result = Expr(
    kind: ExBlock,
    parent: parent,
    blk: blk,
  )
  blk.expr = result

proc new_return_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExReturn,
    parent: parent,
  )
  if val.gene.data.len > 0:
    result.return_val = new_expr(result, val.gene.data[0])

proc new_aspect_expr*(parent: Expr, val: GeneValue): Expr =
  var aspect: Aspect = val
  result = Expr(
    kind: ExAspect,
    parent: parent,
    aspect: aspect,
  )
  aspect.expr = result
  # TODO: convert default values to expressions like below
  # fn.update_matchers(fn.matcher.children)

proc new_advice_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExAdvice,
    parent: parent,
  )
  result.advice = val

proc new_ns_expr*(parent: Expr, val: GeneValue): Expr =
  var name = val.gene.data[0]
  var s: string
  case name.kind:
  of GeneSymbol:
    s = name.symbol
  of GeneComplexSymbol:
    s = name.csymbol.rest[^1]
  else:
    not_allowed()
  var ns = new_namespace(s)
  result = Expr(
    kind: ExNamespace,
    parent: parent,
    ns: ns,
    ns_name: name,
  )
  var body: seq[Expr] = @[]
  for i in 1..<val.gene.data.len:
    body.add(new_expr(parent, val.gene.data[i]))
  result.ns_body = body

proc new_import_expr*(parent: Expr, val: GeneValue): Expr =
  var matcher = new_import_matcher(val)
  result = Expr(
    kind: ExImport,
    parent: parent,
    import_matcher: matcher,
    import_native: val.gene.type.symbol == "import_native",
  )
  if matcher.from != nil:
    result.import_from = new_expr(result, matcher.from)
  if val.gene.props.has_key(PKG_KEY):
    result.import_pkg = new_expr(result, val.gene.props[PKG_KEY])

proc new_class_expr*(parent: Expr, val: GeneValue): Expr =
  var name = val.gene.data[0]
  var s: string
  case name.kind:
  of GeneSymbol:
    s = name.symbol
  of GeneComplexSymbol:
    s = name.csymbol.rest[^1]
  else:
    not_allowed()
  var class = new_class(s)
  result = Expr(
    kind: ExClass,
    parent: parent,
    class: class,
    class_name: name,
  )
  var body_start = 1
  if val.gene.data.len > 2 and val.gene.data[1] == new_gene_symbol("<"):
    body_start = 3
    result.super_class = new_expr(result, val.gene.data[2])
  var body: seq[Expr] = @[]
  for i in body_start..<val.gene.data.len:
    body.add(new_expr(parent, val.gene.data[i]))
  result.class_body = body

proc new_mixin_expr*(parent: Expr, val: GeneValue): Expr =
  var name = val.gene.data[0]
  var s: string
  case name.kind:
  of GeneSymbol:
    s = name.symbol
  of GeneComplexSymbol:
    s = name.csymbol.rest[^1]
  else:
    not_allowed()
  var mix = new_mixin(s)
  result = Expr(
    kind: ExMixin,
    parent: parent,
    mix: mix,
    mix_name: name,
  )
  var body: seq[Expr] = @[]
  for i in 1..<val.gene.data.len:
    body.add(new_expr(parent, val.gene.data[i]))
  result.mix_body = body

proc new_include_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExInclude,
    parent: parent,
  )
  for item in val.gene.data:
    result.include_args.add(new_expr(result, item))

proc new_new_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExNew,
    parent: parent,
  )
  result.new_class = new_expr(parent, val.gene.data[0])
  for i in 1..<val.gene.data.len:
    result.new_args.add(new_expr(result, val.gene.data[i]))

proc new_super_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExSuper,
    parent: parent,
  )
  for item in val.gene.data:
    result.super_args.add(new_expr(result, item))

proc new_method_expr*(parent: Expr, val: GeneValue): Expr =
  if val.gene.type.symbol == "native_method":
    var meth = Method(
      name: val.gene.data[0].symbol_or_str
    )
    result = Expr(
      kind: ExMethod,
      parent: parent,
      meth: meth,
    )
    result.meth_fn_native = new_expr(result, val.gene.data[1])
  else:
    var fn: Function = val # Converter is implicitly called here
    var meth = new_method(nil, fn.name, fn)
    result = Expr(
      kind: ExMethod,
      parent: parent,
      meth: meth,
    )
    fn.expr = result

proc new_invoke_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExInvokeMethod,
    parent: parent,
    invoke_meth: val.gene.props[METHOD_KEY].str.to_key,
  )
  result.invoke_self = new_expr(result, val.gene.props[SELF_KEY])
  for item in val.gene.data:
    result.invoke_args.add(new_expr(result, item))

proc new_eval_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExEval,
    parent: parent,
  )
  if val.gene.props.has_key(SELF_KEY):
    result.eval_self = new_expr(result, val.gene.props[SELF_KEY])
  for i in 0..<val.gene.data.len:
    result.eval_args.add(new_expr(result, val.gene.data[i]))

proc new_caller_eval_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExCallerEval,
    parent: parent,
  )
  for i in 0..<val.gene.data.len:
    result.caller_eval_args.add(new_expr(result, val.gene.data[i]))

proc new_match_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExMatch,
    parent: parent,
    match_pattern: val.gene.data[0],
  )
  result.match_val = new_expr(result, val.gene.data[1])

proc new_quote_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExQuote,
    parent: parent,
  )
  result.quote_val = val.gene.data[0]

proc new_env_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExEnv,
    parent: parent,
  )
  result.env = new_expr(result, val.gene.data[0])
  if val.gene.data.len > 1:
    result.env_default = new_expr(result, val.gene.data[1])

proc new_print_expr*(parent: Expr, val: GeneValue): Expr =
  result = Expr(
    kind: ExPrint,
    parent: parent,
    print_and_return: val.gene.type.symbol == "println",
  )
  if val.gene.props.get_or_default(STDERR_KEY, false):
    result.print_to = new_expr(result, new_gene_symbol("stderr"))
  for item in val.gene.data:
    result.print.add(new_expr(result, item))

proc new_not_expr*(parent: Expr, val: GeneValue): Expr =
  result = new_expr(parent, ExNot)
  result.not = new_expr(result, val.gene.data[0])

proc new_binary_expr*(parent: Expr, `type`: string, val: GeneValue): Expr =
  if val.gene.data[1].is_literal:
    result = Expr(
      kind: ExBinImmediate,
      parent: parent,
    )
    result.bini_first = new_expr(result, val.gene.data[0])
    result.bini_second = val.gene.data[1]
    case `type`:
    of "+":  result.bini_op = BinAdd
    of "-":  result.bini_op = BinSub
    of "*":  result.bini_op = BinMul
    of "/":  result.bini_op = BinDiv
    of "==": result.bini_op = BinEq
    of "!=": result.bini_op = BinNeq
    of "<":  result.bini_op = BinLt
    of "<=": result.bini_op = BinLe
    of ">":  result.bini_op = BinGt
    of ">=": result.bini_op = BinGe
    of "&&": result.bini_op = BinAnd
    of "||": result.bini_op = BinOr
    else: not_allowed()
  else:
    result = Expr(
      kind: ExBinary,
      parent: parent,
    )
    result.bin_first = new_expr(result, val.gene.data[0])
    result.bin_second = new_expr(result, val.gene.data[1])
    case type:
    of "+":  result.bin_op = BinAdd
    of "-":  result.bin_op = BinSub
    of "*":  result.bin_op = BinMul
    of "/":  result.bin_op = BinDiv
    of "==": result.bin_op = BinEq
    of "!=": result.bin_op = BinNeq
    of "<":  result.bin_op = BinLt
    of "<=": result.bin_op = BinLe
    of ">":  result.bin_op = BinGt
    of ">=": result.bin_op = BinGe
    of "&&": result.bin_op = BinAnd
    of "||": result.bin_op = BinOr
    else: not_allowed()

proc new_bin_assignment_expr*(parent: Expr, `type`: string, val: GeneValue): Expr =
  result = Expr(
    kind: ExBinAssignment,
    parent: parent,
  )
  result.bina_first = val.gene.data[0]
  result.bina_second = new_expr(result, val.gene.data[1])
  case `type`:
  of "+=":  result.bina_op = BinAdd
  of "-=":  result.bina_op = BinSub
  of "*=":  result.bina_op = BinMul
  of "/=":  result.bina_op = BinDiv
  else: not_allowed()

proc new_expr*(parent: Expr, kind: ExprKind): Expr =
  result = Expr(
    kind: kind,
    parent: parent,
  )

proc new_expr*(parent: Expr, node: GeneValue): Expr =
  case node.kind:
  of GeneNilKind, GeneBool, GeneInt:
    return new_literal_expr(parent, node)
  of GeneString:
    result = new_expr(parent, ExString)
    result.str = node.str
  of GeneSymbol:
    case node.symbol:
    of "global":
      return new_expr(parent, ExGlobal)
    of "$args":
      return new_expr(parent, ExArgs)
    of "self":
      return new_expr(parent, ExSelf)
    of "return":
      return new_expr(parent, ExReturnRef)
    of "_":
      return new_literal_expr(parent, GenePlaceholder)
    elif node.symbol.endsWith("..."):
      if node.symbol.len == 3: # symbol == "..."
        return new_explode_expr(parent, new_gene_symbol("$args"))
      else:
        return new_explode_expr(parent, new_gene_symbol(node.symbol[0..^4]))
    elif node.symbol.startsWith("@"):
      result = new_expr(parent, ExLiteral)
      result.literal = to_selector(node.symbol)
      return result
    else:
      return new_symbol_expr(parent, node.symbol)
  of GeneComplexSymbol:
    if node.csymbol.first.startsWith("@"):
      result = new_expr(parent, ExLiteral)
      result.literal = to_selector(node.csymbol)
      return result
    else:
      return new_complex_symbol_expr(parent, node)
  of GeneVector:
    node.process_decorators()
    return new_array_expr(parent, node)
  of GeneStream:
    return new_group_expr(parent, node.stream)
  of GeneMap:
    return new_map_expr(parent, node)
  of GeneGene:
    node.normalize()
    if node.gene.type.kind == GeneSymbol:
      if node.gene.type.symbol in SIMPLE_BINARY_OPS:
        return new_binary_expr(parent, node.gene.type.symbol, node)
      elif node.gene.type.symbol in COMPLEX_BINARY_OPS:
        return new_bin_assignment_expr(parent, node.gene.type.symbol, node)
      elif node.gene.type.symbol == "...":
        return new_explode_expr(parent, node.gene.data[0])
      var translator = TranslatorMgr[node.gene.type.symbol.to_key]
      if translator != nil:
        return translator(parent, node)
      for t in CustomTranslators:
        result = t(parent, node)
        if result != nil:
          return result
    # Process decorators like +f, (+g 1)
    node.process_decorators()
    result = new_gene_expr(parent, node)
    result.gene_type = new_expr(result, node.gene.type)
    for k, v in node.gene.props:
      result.gene_props.add(new_map_key_expr(result, k, v))
    for item in node.gene.data:
      result.gene_data.add(new_expr(result, item))
  else:
    return new_literal_expr(parent, node)

TranslatorMgr[ENUM_KEY          ] = proc(parent: Expr, node: GeneValue): Expr =
  var e = new_enum(node.gene.data[0].symbol_or_str)
  var i = 1
  var value = 0
  while i < node.gene.data.len:
    var name = node.gene.data[i].symbol
    i += 1
    if i < node.gene.data.len and node.gene.data[i] == Equal:
      i += 1
      value = node.gene.data[i].int
      i += 1
    e.add_member(name, value)
    value += 1
  result = new_expr(parent, ExEnum)
  result.enum = e

TranslatorMgr[RANGE_KEY         ] = new_range_expr
TranslatorMgr[DO_KEY            ] = new_do_expr
TranslatorMgr[LOOP_KEY          ] = new_loop_expr
TranslatorMgr[WHILE_KEY         ] = new_while_expr
TranslatorMgr[FOR_KEY           ] = new_for_expr
TranslatorMgr[BREAK_KEY         ] = new_break_expr
TranslatorMgr[CONTINUE_KEY      ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExContinue)
TranslatorMgr[IF_KEY            ] = new_if_expr
TranslatorMgr[NOT_KEY           ] = new_not_expr
TranslatorMgr[VAR_KEY           ] = new_var_expr
TranslatorMgr[THROW_KEY         ] = new_throw_expr
TranslatorMgr[TRY_KEY           ] = new_try_expr
TranslatorMgr[FN_KEY            ] = new_fn_expr
TranslatorMgr[MACRO_KEY         ] = new_macro_expr
TranslatorMgr[RETURN_KEY        ] = new_return_expr
TranslatorMgr[ASPECT_KEY        ] = new_aspect_expr
TranslatorMgr[BEFORE_KEY        ] = new_advice_expr
TranslatorMgr[AFTER_KEY         ] = new_advice_expr
TranslatorMgr[NS_KEY            ] = new_ns_expr
TranslatorMgr[IMPORT_KEY        ] = new_import_expr
TranslatorMgr[IMPORT_NATIVE_KEY ] = new_import_expr
TranslatorMgr[DOLLAR_INCLUDE_KEY] = proc(parent: Expr, node: GeneValue): Expr =
  result = Expr(
    kind: ExIncludeFile,
    parent: parent,
  )
  result.include_file = new_expr(result, node.gene.data[0])
TranslatorMgr[STOP_INHERITANCE_KEY] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExStopInheritance)
TranslatorMgr[CLASS_KEY         ] = new_class_expr
TranslatorMgr[OBJECT_KEY        ] = proc(parent: Expr, node: GeneValue): Expr =
  var name = node.gene.data[0]
  result = Expr(
    kind: ExObject,
    parent: parent,
    obj_name: name,
  )
  var body_start = 1
  if node.gene.data.len > 2 and node.gene.data[1] == new_gene_symbol("<"):
    body_start = 3
    result.obj_super_class = new_expr(result, node.gene.data[2])
  var body: seq[Expr] = @[]
  for i in body_start..<node.gene.data.len:
    body.add(new_expr(parent, node.gene.data[i]))
  result.obj_body = body
TranslatorMgr[METHOD_KEY        ] = new_method_expr
TranslatorMgr[NATIVE_METHOD_KEY ] = new_method_expr
TranslatorMgr[NEW_KEY           ] = new_new_expr
TranslatorMgr[SUPER_KEY         ] = new_super_expr
TranslatorMgr[INVOKE_METHOD_KEY ] = new_invoke_expr
TranslatorMgr[MIXIN_KEY         ] = new_mixin_expr
TranslatorMgr[INCLUDE_KEY       ] = new_include_expr
TranslatorMgr[PARSE_KEY         ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExParse)
  result.parse = new_expr(parent, node.gene.data[0])
TranslatorMgr[EVAL_KEY          ] = new_eval_expr
TranslatorMgr[CALLER_EVAL_KEY   ] = new_caller_eval_expr
TranslatorMgr[MATCH_KEY         ] = new_match_expr
TranslatorMgr[QUOTE_KEY         ] = new_quote_expr
TranslatorMgr[UNQUOTE_KEY       ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExExit)
  result.unquote_val = node.gene.data[0]
# TranslatorMgr["..."           ] = new_explode_expr
TranslatorMgr[ENV_KEY           ] = new_env_expr
TranslatorMgr[EXIT_KEY          ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExExit)
  if node.gene.data.len > 0:
    result.exit = new_expr(parent, node.gene.data[0])
TranslatorMgr[PRINT_KEY         ] = new_print_expr
TranslatorMgr[PRINTLN_KEY       ] = new_print_expr
TranslatorMgr[EQ_KEY            ] = new_assignment_expr

TranslatorMgr[CALL_KEY          ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExCall)
  # for k, v in node.gene.props:
  #   result.call_props[k] = new_expr(parent, v)
  result.call_target = new_expr(result, node.gene.data[0])
  if node.gene.data.len > 2:
    not_allowed("Syntax error: too many parameters are passed to (call).")
  elif node.gene.data.len > 1:
    result.call_args = new_expr(result, node.gene.data[1])

TranslatorMgr[GET_KEY           ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExGet)
  result.get_target = new_expr(result, node.gene.data[0])
  result.get_index = new_expr(result, node.gene.data[1])

TranslatorMgr[SET_KEY           ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExGet)
  result = new_expr(parent, ExSet)
  result.set_target = new_expr(result, node.gene.data[0])
  result.set_index = new_expr(result, node.gene.data[1])
  result.set_value = new_expr(result, node.gene.data[2])

TranslatorMgr[DEF_MEMBER_KEY    ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExDefMember)
  result.def_member_name = new_expr(result, node.gene.data[0])
  result.def_member_value = new_expr(result, node.gene.data[1])

TranslatorMgr[DEF_NS_MEMBER_KEY ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExDefNsMember)
  result.def_ns_member_name = new_expr(result, node.gene.data[0])
  result.def_ns_member_value = new_expr(result, node.gene.data[1])

TranslatorMgr[GET_CLASS_KEY     ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExGetClass)
  result.get_class_val = new_expr(result, node.gene.data[0])

TranslatorMgr[BLOCK_KEY         ] = proc(parent: Expr, node: GeneValue): Expr =
  return new_block_expr(parent, node)

TranslatorMgr[TODO_KEY          ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExTodo)
  if node.gene.data.len > 0:
    result.todo = new_expr(result, node.gene.data[0])

TranslatorMgr[NOT_ALLOWED_KEY   ] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExNotAllowed)
  if node.gene.data.len > 0:
    result.not_allowed = new_expr(result, node.gene.data[0])

TranslatorMgr[PARSE_CMD_ARGS_KEY] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExParseCmdArgs)
  var m = new_cmd_args_matcher()
  m.parse(node.gene.data[0])
  result.cmd_args_schema = m
  result.cmd_args = new_expr(result, node.gene.data[1])

TranslatorMgr[REPL_KEY] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExRepl)

TranslatorMgr[ASYNC_KEY] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExAsync)
  result.async = new_expr(result, node.gene.data[0])

TranslatorMgr[AWAIT_KEY] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExAwait)
  result.await = @[]
  for item in node.gene.data:
    result.await.add(new_expr(result, item))

TranslatorMgr[ON_FUTURE_SUCCESS_KEY] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExAsyncCallback)
  result.acb_success = true
  result.acb_self = new_expr(result, node.gene.data[0])
  result.acb_callback = new_expr(result, node.gene.data[1])

TranslatorMgr[ON_FUTURE_FAILURE_KEY] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExAsyncCallback)
  result.acb_success = false
  result.acb_self = new_expr(result, node.gene.data[0])
  result.acb_callback = new_expr(result, node.gene.data[1])

TranslatorMgr[SELECTOR_KEY] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExSelector)
  for item in node.gene.data:
    result.selector.add(new_expr(result, item))

TranslatorMgr[SELECTOR_PARALLEL_KEY] = proc(parent: Expr, node: GeneValue): Expr =
  result = new_expr(parent, ExSelector)
  result.parallel_mode = true
  for item in node.gene.data:
    result.selector.add(new_expr(result, item))

TranslatorMgr[CASE_KEY] = proc(parent: Expr, node: GeneValue): Expr =
  # Create a variable because result can not be accessed from closure.
  var expr = new_expr(parent, ExCase)
  expr.case_input = new_expr(result, node.gene.data[0])

  var state = CsInput
  var cond: GeneValue
  var logic: seq[GeneValue]

  proc update_mapping(cond: GeneValue, logic: seq[GeneValue]) =
    var index = expr.case_blks.len
    expr.case_blks.add(new_group_expr(expr, logic))
    if cond.kind == GeneVector:
      for item in cond.vec:
        expr.case_more_mapping.add((new_expr(expr, item), index))
    else:
      expr.case_more_mapping.add((new_expr(expr, cond), index))

  proc handler(input: GeneValue) =
    case state:
    of CsInput:
      if input == When:
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
      elif input == When:
        state = CsWhen
        update_mapping(cond, logic)
      elif input == Else:
        state = CsElse
        update_mapping(cond, logic)
        logic = @[]
      else:
        logic.add(input)
    of CsElse:
      if input == nil:
        expr.case_else = new_group_expr(expr, logic)
      else:
        logic.add(input)

  var i = 1
  while i < node.gene.data.len:
    handler(node.gene.data[i])
    i += 1
  handler(nil)

  result = expr

import tables, os, nre, options

import ./map_key
import ./types
import ./parser

#################### Definitions #################

proc reload_module*(self: VirtualMachine, frame: Frame, name: string, code: string)
proc translate*(value: Value): Expr
proc translate*(stmts: seq[Value]): Expr

var hot_reload_counter = 0
template check_hot_reload*(self: VirtualMachine) =
  hot_reload_counter += 1
  if hot_reload_counter == 5:
    hot_reload_counter = 0
    let tried = HotReloadListener.try_recv()
    if tried.data_available:
      echo "check_hot_reload " & tried.msg
      let match = tried.msg.match(re(get_current_dir() & "/(.*)" & "\\.gene"))
      # Not sure why I have to use options.is_some/get and nre.captures here. Maybe there is some name collisions?
      if options.is_some(match):
        let module_name = nre.captures(options.get(match))[0]
        echo "check_hot_reload " & module_name
        var frame = new_frame()
        self.reload_module(frame, module_name, read_file(tried.msg))

template eval*(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  self.check_hot_reload()
  expr.evaluator(self, frame, nil, expr)

proc prepare*(self: VirtualMachine, code: string): Value =
  var parsed = read_all(code)
  case parsed.len:
  of 0:
    Nil
  of 1:
    parsed[0]
  else:
    new_gene_stream(parsed)

proc reload_module*(self: VirtualMachine, frame: Frame, name: string, code: string) =
  var loaded_module = self.modules[name.to_key]
  if loaded_module.is_nil:
    not_allowed("reload_module: " & loaded_module.name & " must be imported before being reloaded.")
  elif not loaded_module.reloadable:
    not_allowed("reload_module: " & loaded_module.name & " is not reloadable.")

  var module = new_module(name)
  var new_frame = new_frame()
  new_frame.ns = module.ns
  new_frame.scope = new_scope()
  var parsed = self.prepare(code)
  var expr = translate(parsed)
  discard self.eval(new_frame, expr)
  self.modules[name.to_key] = module

#################### Expr ########################

proc eval_todo*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  todo()

proc eval_never*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  raise new_exception(types.Exception, "eval_never should never be called.")

#################### ExLiteral ###################

type
  ExLiteral* = ref object of Expr
    data*: Value

proc eval_literal(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  cast[ExLiteral](expr).data

proc new_ex_literal*(v: Value): ExLiteral =
  ExLiteral(
    evaluator: eval_literal,
    data: v,
  )

#################### ExLiteral ###################

type
  ExString* = ref object of Expr
    data*: string

proc eval_string(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  return "" & cast[ExString](expr).data

proc new_ex_string*(v: Value): ExString =
  ExString(
    evaluator: eval_string,
    data: v.str,
  )

#################### ExGroup #####################

type
  ExGroup* = ref object of Expr
    data*: seq[Expr]

proc eval_group*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  for item in cast[ExGroup](expr).data.mitems:
    result = self.eval(frame, item)

proc new_ex_group*(): ExGroup =
  result = ExGroup(
    evaluator: eval_group,
  )

#################### ExExplode ###################

type
  ExExplode* = ref object of Expr
    data*: Expr

proc eval_explode*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var data = self.eval(frame, cast[ExExplode](expr).data)
  Value(
    kind: VkExplode,
    explode: data,
  )

proc new_ex_explode*(): ExExplode =
  result = ExExplode(
    evaluator: eval_explode,
  )

#################### ExSelf ######################

type
  ExSelf* = ref object of Expr

proc eval_self(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  frame.self

proc new_ex_self*(): ExSelf =
  ExSelf(
    evaluator: eval_self,
  )

#################### ExNsDef #####################

type
  ExNsDef* = ref object of Expr
    name*: MapKey
    value*: Expr

proc eval_ns_def(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExNsDef](expr)
  result = self.eval(frame, e.value)
  frame.ns[e.name] = result

proc new_ex_ns_def*(): ExNsDef =
  result = ExNsDef(
    evaluator: eval_ns_def,
  )

#################### ExGene ######################

type
  ExGene* = ref object of Expr
    `type`*: Expr
    args*: Value        # The unprocessed args
    args_expr*: Expr    # The translated args

#################### ExArguments #################

type
  ExArguments* = ref object of Expr
    props*: Table[MapKey, Expr]
    data*: seq[Expr]

proc eval_args(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  todo()

proc new_ex_arg*(): ExArguments =
  result = ExArguments(
    evaluator: eval_args,
  )

#################### ExBreak #####################

type
  ExBreak* = ref object of Expr

proc eval_break*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e: Break
  e.new
  raise e

proc new_ex_break*(): ExBreak =
  result = ExBreak(
    evaluator: eval_break,
  )

##################################################

type
  ExSymbol* = ref object of Expr
    name*: MapKey

  # Special case
  # ExName* = ref object of Expr
  #   name*: MapKey

  ExNames* = ref object of Expr
    names*: seq[MapKey]

proc eval_names*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var e = cast[ExNames](expr)
  case e.names[0]:
  of GLOBAL_KEY:
    result = GLOBAL_NS
  else:
    result = frame.scope[e.names[0]]

  if result == nil:
    result = frame.ns[e.names[0]]
  # for name in e.names[1..^1]:
  #   result = result.get_member(name)

proc new_ex_names*(self: Value): ExNames =
  var e = ExNames(
    evaluator: eval_names,
  )
  for s in self.csymbol:
    e.names.add(s.to_key)
  result = e

#################### ExSetProp ###################

type
  ExSetProp* = ref object of Expr
    name*: MapKey
    value*: Expr

  # ExGetProp* = ref object of Expr
  #   name*: MapKey

proc eval_set_prop*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var value = cast[ExSetProp](expr).value
  result = self.eval(frame, value)
  frame.self.instance_props[cast[ExSetProp](expr).name] = result

proc new_ex_set_prop*(name: string, value: Expr): ExSetProp =
  ExSetProp(
    evaluator: eval_set_prop,
    name: name.to_key,
    value: value,
  )

# proc eval_get_prop*(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
#   frame.self.instance_props[cast[ExGetProp](expr).name]

# proc new_ex_get_prop*(name: string): ExGetProp =
#   ExGetProp(
#     evaluator: eval_get_prop,
#     name: name.to_key,
#   )

#################### Selector ####################

type
  ExInvokeSelector* = ref object of Expr
    self*: Expr
    data*: seq[Expr]

##################################################

var Translators*     = Table[ValueKind, Translator]()
var GeneTranslators* = Table[string, Translator]()

##################################################

proc default_translator(value: Value): Expr =
  case value.kind:
  of VkNil, VkBool, VkInt, VkFloat, VkRegex, VkTime:
    return new_ex_literal(value)
  of VkString:
    return new_ex_string(value)
  of VkStream:
    return translate(value.stream)
  else:
    todo($value.kind)

proc translate*(value: Value): Expr =
  var translator = Translators.get_or_default(value.kind, default_translator)
  translator(value)

proc translate*(stmts: seq[Value]): Expr =
  case stmts.len:
  of 0:
    result = new_ex_literal(Nil)
  of 1:
    result = translate(stmts[0])
  else:
    result = new_ex_group()
    for stmt in stmts:
      cast[ExGroup](result).data.add(translate(stmt))

# (@p = 1)
proc translate_prop_assignment*(value: Value): Expr =
  var name = value.gene_type.symbol[1..^1]
  return new_ex_set_prop(name, translate(value.gene_data[1]))

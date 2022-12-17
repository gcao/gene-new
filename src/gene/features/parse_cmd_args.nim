import strutils, sequtils, tables

import ../types
import ../interpreter_base

type
  ExParseCmdArgs* = ref object of Expr
    cmd_args_schema*: ArgMatcherRoot
    cmd_args*: Expr

  ArgMatcherRoot* = ref object
    include_program*: bool
    options*: Table[string, ArgMatcher]
    args*: seq[ArgMatcher]
    # Extra is always returned if "-- ..." is found.

  ArgMatcherKind* = enum
    ArgOption      # options
    ArgPositional  # positional arguments

  ArgDataType* = enum
    ArgInt
    ArgBool
    ArgString

  ArgMatcher* = ref object
    case kind*: ArgMatcherKind
    of ArgOption:
      short_name*: string
      long_name*: string
      toggle*: bool          # if false, expect a value
    of ArgPositional:
      arg_name*: string
    description*: string
    required*: bool
    multiple*: bool
    data_type*: ArgDataType  # int, string, what else?
    default: Value

  ArgMatchingResultKind* = enum
    AmSuccess
    AmFailure

  ArgMatchingResult* = ref object
    kind*: ArgMatchingResultKind
    program*: string
    options*: Table[string, Value]
    args*: Table[string, Value]
    extra*: seq[string]
    failure*: string  # if kind == AmFailure

proc new_cmd_args_matcher*(): ArgMatcherRoot =
  return ArgMatcherRoot(
    options: Table[string, ArgMatcher](),
  )

proc name*(self: ArgMatcher): string =
  case self.kind:
  of ArgOption:
    if self.long_name == "":
      return self.short_name
    else:
      return self.long_name
  of ArgPositional:
    return self.arg_name

proc default_value*(self: ArgMatcher): Value =
  case self.data_type:
  of ArgInt:
    if self.default == nil:
      if self.multiple:
        return @[]
      else:
        return 0
    else:
      return self.default
  of ArgBool:
    if self.default == nil:
      if self.multiple:
        return @[]
      else:
        return false
    else:
      return self.default
  of ArgString:
    if self.default == nil:
      if self.multiple:
        return @[]
      else:
        return ""
    else:
      return self.default

proc fields*(self: ArgMatchingResult): Table[string, Value] =
  for k, v in self.options:
    result[k] = v
  for k, v in self.args:
    result[k] = v

proc parse_data_type(self: var ArgMatcher, input: Value) =
  var value = input.gene_type
  if value == new_gene_symbol("int"):
    self.data_type = ArgInt
  elif value == new_gene_symbol("bool"):
    self.data_type = ArgBool
  else:
    self.data_type = ArgString

proc parse*(self: var ArgMatcherRoot, schema: Value) =
  if schema.vec.len == 0:
    return
  if schema.vec[0] == new_gene_symbol("program"):
    self.include_program = true
  for i, item in schema.vec:
    # Check whether first item is program
    if i == 0 and item == new_gene_symbol("program"):
      self.include_program = true
      continue

    case item.gene_type.str:
    of "option":
      var option = ArgMatcher(kind: ArgOption)
      option.parse_data_type(item)
      option.toggle = item.gene_props.get_or_default("toggle", false)
      if option.toggle:
        option.data_type = ArgBool
      else:
        option.multiple = item.gene_props.get_or_default("multiple", false)
        option.required = item.gene_props.get_or_default("required", false)
      if item.gene_props.has_key("default"):
        option.default = item.gene_props["default"]
        option.required = false
      for item in item.gene_children:
        if item.str[0] == '-':
          if item.str.len == 2:
            option.short_name = item.str
          else:
            option.long_name = item.str
        else:
          option.description = item.str

      if option.short_name != "":
        self.options[option.short_name] = option
      if option.long_name != "":
        self.options[option.long_name] = option

    of "argument":
      var arg = ArgMatcher(kind: ArgPositional)
      arg.arg_name = item.gene_children[0].str
      if item.gene_props.has_key("default"):
        arg.default = item.gene_props["default"]
        arg.required = false
      arg.parse_data_type(item)
      var is_last = i == schema.vec.len - 1
      if is_last:
        arg.multiple = item.gene_props.get_or_default("multiple", false)
        arg.required = item.gene_props.get_or_default("required", false)
      else:
        arg.required = true
      self.args.add(arg)

    else:
      not_allowed()

proc translate(self: ArgMatcher, value: string): Value =
  if self.data_type == ArgInt:
    return value.parse_int
  elif self.data_type == ArgBool:
    return value.parse_bool
  else:
    return new_gene_string(value)

proc match*(self: var ArgMatcherRoot, input: seq[string]): ArgMatchingResult =
  result = ArgMatchingResult(kind: AmSuccess)
  var arg_index = 0

  var i = 0
  if self.include_program:
    result.program = input[i]
    i += 1
  var in_extra = false
  while i < input.len:
    var item = input[i]
    i += 1
    if in_extra:
      result.extra.add(item)
    elif item == "--":
      in_extra = true
      continue
    elif item[0] == '-':
      if self.options.has_key(item):
        var option = self.options[item]
        if option.toggle:
          result.options[option.name] = true
        else:
          var value = input[i]
          i += 1
          if option.multiple:
            for s in value.split(","):
              var v = option.translate(s)
              if result.options.has_key(option.name):
                result.options[option.name].vec.add(v)
              else:
                result.options[option.name] = @[v]
          else:
            result.options[option.name] = option.translate(value)
      else:
        echo "Unknown option: " & $item
    else:
      if arg_index < self.args.len:
        var arg = self.args[arg_index]
        var value = arg.translate(item)
        if arg.multiple:
          if result.args.has_key(arg.name):
            result.args[arg.name].vec.add(value)
          else:
            result.args[arg.name] = @[value]
        else:
          arg_index += 1
          result.args[arg.name] = value
      else:
        echo "Too many arguments are found. Ignoring " & $item

  # Assign values for mandatory options and arguments
  for _, v in self.options:
    if not result.options.has_key(v.name):
      if v.required:
        raise new_exception(ArgumentError, "Missing mandatory option: " & v.name)
      else:
        result.options[v.name] = v.default_value

  for v in self.args:
    if not result.args.has_key(v.name):
      if v.required:
        raise new_exception(ArgumentError, "Missing mandatory argument: " & v.name)
      else:
        result.args[v.name] = v.default_value

proc match*(self: var ArgMatcherRoot, input: string): ArgMatchingResult =
  var parts: seq[string]
  var s = strutils.strip(input, leading=true)
  if s.len > 0:
    parts = s.split(" ")
  return self.match(parts)

proc eval_parse(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExParseCmdArgs](expr)
  var cmd_args = self.eval(frame, expr.cmd_args)
  var r = expr.cmd_args_schema.match(cmd_args.vec.map(proc(v: Value): string = v.str))
  if r.kind == AmSuccess:
    for k, v in r.fields:
      var name = k
      if k.starts_with("--"):
        name = k[2..^1]
      elif k.starts_with("-"):
        name = k[1..^1]
      frame.scope.def_member(name, v)
  else:
    todo()

proc translate_parse(value: Value): Expr =
  var r = ExParseCmdArgs(
    evaluator: eval_parse,
    cmd_args: translate(value.gene_children[1]),
  )
  var m = new_cmd_args_matcher()
  m.parse(value.gene_children[0])
  r.cmd_args_schema = m
  return r

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    self.global_ns.ns["$parse_cmd_args"] = new_gene_processor(translate_parse)
    self.gene_ns.ns["$parse_cmd_args"] = self.global_ns.ns["$parse_cmd_args"]

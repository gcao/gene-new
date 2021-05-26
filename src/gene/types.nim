import os, re, strutils, tables, unicode, hashes, sets, json, asyncdispatch, times, strformat

import ./map_key

const DEFAULT_ERROR_MESSAGE = "Error occurred."

type
  Catchable* = object of CatchableError

  Exception* = object of Catchable
    instance*: Value  # instance of Gene exception class

  NotDefinedException* = object of Exception

  # index of a name in a scope
  NameIndexScope* = distinct int

  Translator* = proc(value: Value): Expr
  Evaluator* = proc(self: VirtualMachine, frame: Frame, expr: var Expr): Value
  Invoker* = proc(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value

  GeneProcessor* = ref object of RootObj
    translator*: Translator
    invoker*: Invoker

  Runtime* = ref object
    name*: string     # default/...
    home*: string     # GENE_HOME directory
    version*: string
    features*: Table[string, Feature]
    props*: Table[string, Value]  # Additional properties

  # To group functionality like oop, macro, repl
  # Features should be divided into core features (e.g. if, var, namespace etc)
  # and non-core features (e.g. repl etc)
  Feature* = ref object
    parent*: Feature
    key*: string                  # E.g. oop
    name*: string                 # E.g. Object Oriented Programming
    description*: string          # E.g. More descriptive information about the feature
    props*: Table[string, Value]  # Additional properties
    children*: seq[Feature]

  ## This is the root of a running application
  Application* = ref object
    name*: string         # default to base name of command
    pkg*: Package         # Entry package for the application
    ns*: Namespace
    cmd*: string
    args*: seq[string]
    props*: Table[string, Value]  # Additional properties

  Package* = ref object
    dir*: string          # Where the package assets are installed
    adhoc*: bool          # Adhoc package is created when package.gene is not found
    ns*: Namespace
    name*: string
    version*: Value
    license*: Value
    dependencies*: Table[string, Package]
    homepage*: string
    props*: Table[string, Value]  # Additional properties
    doc*: Document    # content of package.gene

  Module* = ref object
    pkg*: Package         # Package in which the module belongs, or stdlib if not set
    name*: string
    root_ns*: Namespace
    props*: Table[string, Value]  # Additional properties

  Namespace* = ref object
    parent*: Namespace
    stop_inheritance*: bool  # When set to true, stop looking up for members
    name*: string
    members*: Table[MapKey, Value]

  Scope* = ref object
    parent*: Scope
    parent_index_max*: NameIndexScope
    members*:  seq[Value]
    # Value of mappings is composed of two bytes:
    #   first is the optional index in self.mapping_history + 1
    #   second is the index in self.members
    mappings*: Table[MapKey, int]
    mapping_history*: seq[seq[NameIndexScope]]

  Class* = ref object
    parent*: Class
    name*: string
    methods*: Table[MapKey, Method]
    ns*: Namespace # Class can act like a namespace

  Mixin* = ref object
    name*: string
    methods*: Table[MapKey, Method]
    # TODO: ns*: Namespace # Mixin can act like a namespace

  Method* = ref object
    class*: Class
    name*: string
    fn*: Function
    # public*: bool

  Instance* = ref object
    class*: Class
    value*: Value

  Function* = ref object of GeneProcessor
    async*: bool
    ns*: Namespace
    parent_scope*: Scope
    parent_scope_max*: NameIndexScope
    name*: string
    matcher*: RootMatcher
    matching_hint*: MatchingHint
    body*: seq[Value]
    body_compiled*: Expr

  Block* = ref object of GeneProcessor
    frame*: Frame
    parent_scope_max*: NameIndexScope
    matcher*: RootMatcher
    body*: seq[Value]

  Macro* = ref object of GeneProcessor
    ns*: Namespace
    name*: string
    matcher*: RootMatcher
    body*: seq[Value]

  Enum* = ref object
    name*: string
    members*: OrderedTable[string, EnumMember]

  EnumMember* = ref object
    parent*: Enum
    name*: string
    value*: int

  ComplexSymbol* = ref object
    first*: string
    rest*: seq[string]

  # applicable to numbers, characters
  Range* = ref object
    first*: Value
    last*: Value
    step*: Value # default to 1 if first is greater than last
    # include_first*: bool # always true
    include_last*: bool # default to false

  # Non-date specific time object
  Time* = ref object
    hour*: int
    minute*: int
    second*: int
    timezone*: Timezone

  DateTimeInternal = ref object
    data: DateTime

  ValueKind* = enum
    VkNil
    VkAny
    VkCustom
    VkBool
    VkInt
    VkRatio
    VkFloat
    VkChar
    VkString
    VkSymbol
    VkComplexSymbol
    VkRegex
    VkRange
    # Time part should be 00:00:00 and timezone should not matter
    VkDate
    # Date + time + timezone
    VkDateTime
    VkTimeKind
    VkTimezone
    VkMap
    VkVector
    VkSet
    VkGene
    VkStream
    VkDocument
    VkPlaceholder
    # Internal types
    VkException = 128
    VkExpr
    VkGeneProcessor
    VkApplication
    VkPackage
    VkModule
    VkNamespace
    VkFunction
    VkMacro
    VkBlock
    VkReturn
    VkClass
    VkMixin
    VkMethod
    VkInstance
    VkEnum
    VkEnumMember
    VkExplode
    VkFile

  Value* {.acyclic.} = ref object
    case kind*: ValueKind
    of VkAny:
      any_type*: MapKey   # Optional type info
      any*: pointer
    of VkCustom:
      custom*: CustomValue
    of VkBool:
      bool*: bool
    of VkInt:
      int*: BiggestInt
    of VkRatio:
      ratio_num*: BiggestInt
      ratio_denom*: BiggestInt
    of VkFloat:
      float*: float
    of VkChar:
      char*: char
      rune*: Rune
    of VkString:
      str*: string
    of VkSymbol:
      symbol*: string
    of VkComplexSymbol:
      csymbol*: seq[string]
    of VkRegex:
      regex*: Regex
    of VkRange:
      range_start*: Value
      range_end*: Value
      range_incl_start*: bool
      range_incl_end*: bool
    of VkDate, VkDateTime:
      date_internal: DateTimeInternal
    of VkTimeKind:
      time*: Time
    of VkTimezone:
      timezone*: Timezone
    of VkMap:
      map*: OrderedTable[MapKey, Value]
    of VkVector:
      vec*: seq[Value]
    of VkSet:
      set*: OrderedSet[Value]
    of VkGene:
      gene_type*: Value
      gene_props*: OrderedTable[MapKey, Value]
      gene_data*: seq[Value]
    of VkStream:
      stream*: seq[Value]
    # Internal types
    of VkExpr:
      expr*: Expr
    of VkGeneProcessor:
      gene_processor*: GeneProcessor
    of VkNamespace:
      ns*: Namespace
    of VkFunction:
      fn*: Function
    else:
      discard

  Expr* = ref object of RootObj
    evaluator*: Evaluator

  CustomValue* = ref object of RootObj

  Document* = ref object
    `type`: Value
    props*: OrderedTable[MapKey, Value]
    data*: seq[Value]

  VirtualMachine* = ref object
    app*: Application
    modules*: OrderedTable[MapKey, Namespace]
    repl_on_error*: bool
    gene_ns*: Value
    genex_ns*: Value
    object_class*: Value
    class_class*: Value
    exception_class*: Value

  FrameKind* = enum
    FrFunction
    FrMacro
    FrMethod
    FrModule
    FrBody

  FrameExtra* = ref object
    case kind*: FrameKind
    of FrFunction:
      fn*: Function
    of FrMacro:
      mac*: Function
    of FrMethod:
      class*: Class
      meth*: Function
      meth_name*: MapKey
      # hierarchy*: CallHierarchy # A hierarchy object that tracks where the method is in class hierarchy
    else:
      discard

  Frame* = ref object
    parent*: Frame
    self*: Value
    ns*: Namespace
    scope*: Scope
    args*: Value # This is only available in some frames (e.g. function/macro/block)
    extra*: FrameExtra

  Break* = ref object of Catchable
    val*: Value

  Continue* = ref object of Catchable

  Return* = ref object of Catchable
    frame*: Frame
    val*: Value

  MatchMode* = enum
    MatchDefault
    MatchArgs

  MatchingMode* = enum
    MatchArgParsing # (fn f [a b] ...)
    MatchExpression # (match [a b] input): a and b will be defined
    MatchAssignment # ([a b] = input): a and b must be defined first

  # Match the whole input or the first child (if running in ArgumentMode)
  # Can have name, match nothing, or have group of children
  RootMatcher* = ref object
    mode*: MatchingMode
    children*: seq[Matcher]

  MatchingHintMode* = enum
    MhDefault
    MhNone
    MhSimpleData  # E.g. [a b]

  MatchingHint* = object
    mode*: MatchingHintMode

  MatcherKind* = enum
    MatchOp
    MatchProp
    MatchData

  Matcher* = ref object
    root*: RootMatcher
    kind*: MatcherKind
    name*: MapKey
    # match_name*: bool # Match symbol to name - useful for (myif true then ... else ...)
    default_value*: Value
    default_value_expr*: Expr
    splat*: bool
    min_left*: int # Minimum number of args following this
    children*: seq[Matcher]
    # required*: bool # computed property: true if splat is false and default value is not given

  MatchResultKind* = enum
    MatchSuccess
    MatchMissingFields
    MatchWrongType # E.g. map is passed but array or gene is expected

  MatchedField* = ref object
    name*: MapKey
    value*: Value # Either value_expr or value must be given
    value_expr*: Expr

  MatchResult* = ref object
    message*: string
    kind*: MatchResultKind
    # If success
    fields*: seq[MatchedField]
    assign_only*: bool # If true, no new variables will be defined
    # If missing fields
    missing*: seq[MapKey]
    # If wrong type
    expect_type*: string
    found_type*: string

  # Internal state when applying the matcher to an input
  # Limited to one level
  MatchState* = ref object
    # prop_processed*: seq[MapKey]
    data_index*: int

  # Types related to command line argument parsing
  ArgumentError* = object of Exception

let
  Nil*   = Value(kind: VkNil)
  True*  = Value(kind: VkBool, bool: true)
  False* = Value(kind: VkBool, bool: false)
  Placeholder* = Value(kind: VkPlaceholder)

  Quote*     = Value(kind: VkSymbol, symbol: "quote")
  Unquote*   = Value(kind: VkSymbol, symbol: "unquote")
  If*        = Value(kind: VkSymbol, symbol: "if")
  Then*      = Value(kind: VkSymbol, symbol: "then")
  Elif*      = Value(kind: VkSymbol, symbol: "elif")
  Else*      = Value(kind: VkSymbol, symbol: "else")
  When*      = Value(kind: VkSymbol, symbol: "when")
  Not*       = Value(kind: VkSymbol, symbol: "not")
  Equal*     = Value(kind: VkSymbol, symbol: "=")
  Try*       = Value(kind: VkSymbol, symbol: "try")
  Catch*     = Value(kind: VkSymbol, symbol: "catch")
  Finally*   = Value(kind: VkSymbol, symbol: "finally")
  Call*      = Value(kind: VkSymbol, symbol: "call")
  Do*        = Value(kind: VkSymbol, symbol: "do")

var Ints: array[111, Value]
for i in 0..110:
  Ints[i] = Value(kind: VkInt, int: i - 10)

var VM*: VirtualMachine   # The current virtual machine

var ObjectClass*   : Value
var ClassClass*    : Value
var ExceptionClass*: Value

#################### Definitions #################

proc new_gene_int*(val: BiggestInt): Value
proc new_gene_string*(s: string): Value {.gcsafe.}
proc new_gene_string_move*(s: string): Value
proc new_gene_vec*(items: seq[Value]): Value {.gcsafe.}
proc new_namespace*(): Namespace
proc new_namespace*(parent: Namespace): Namespace
proc new_match_matcher*(): RootMatcher
proc new_arg_matcher*(): RootMatcher
proc hint*(self: RootMatcher): MatchingHint
proc parse*(self: var RootMatcher, v: Value)

##################################################

proc identity*[T](v: T): T = v

proc todo*() =
  raise new_exception(Exception, "TODO")

proc todo*(message: string) =
  raise new_exception(Exception, "TODO: " & message)

proc not_allowed*(message: string) =
  raise new_exception(Exception, message)

proc not_allowed*() =
  not_allowed("Error: should not arrive here.")

proc new_gene_exception*(message: string, instance: Value): ref Exception =
  var e = new_exception(Exception, message)
  e.instance = instance
  return e

proc new_gene_exception*(message: string): ref Exception =
  return new_gene_exception(message, nil)

proc new_gene_exception*(instance: Value): ref Exception =
  return new_gene_exception(DEFAULT_ERROR_MESSAGE, instance)

proc new_gene_exception*(): ref Exception =
  return new_gene_exception(DEFAULT_ERROR_MESSAGE, nil)

proc date*(self: Value): DateTime =
  self.date_internal.data

#################### Converters ##################

converter int_to_gene*(v: int): Value = new_gene_int(v)
converter int_to_gene*(v: int64): Value = new_gene_int(v)
converter biggest_to_int*(v: BiggestInt): int = cast[int](v)

converter seq_to_gene*(v: seq[Value]): Value {.gcsafe.} = new_gene_vec(v)
converter str_to_gene*(v: string): Value {.gcsafe.} = new_gene_string(v)

converter to_map*(self: OrderedTable[string, Value]): OrderedTable[MapKey, Value] {.inline.} =
  for k, v in self:
    result[k.to_key] = v

converter to_string_map*(self: OrderedTable[MapKey, Value]): OrderedTable[string, Value] {.inline.} =
  for k, v in self:
    result[k.to_s] = v

converter int_to_scope_index*(v: int): NameIndexScope = cast[NameIndexScope](v)
converter scope_index_to_int*(v: NameIndexScope): int = cast[int](v)

converter gene_to_ns*(v: Value): Namespace = todo()

#################### Module ######################

proc new_module*(name: string): Module =
  result = Module(
    name: name,
    root_ns: new_namespace(VM.app.ns),
  )

proc new_module*(): Module =
  result = new_module("<unknown>")

proc new_module*(ns: Namespace, name: string): Module =
  result = Module(
    name: name,
    root_ns: new_namespace(ns),
  )

proc new_module*(ns: Namespace): Module =
  result = new_module(ns, "<unknown>")

#################### Namespace ###################

proc new_namespace*(): Namespace =
  return Namespace(
    name: "<root>",
    members: Table[MapKey, Value](),
  )

proc new_namespace*(parent: Namespace): Namespace =
  return Namespace(
    parent: parent,
    name: "<root>",
    members: Table[MapKey, Value](),
  )

proc new_namespace*(name: string): Namespace =
  return Namespace(
    name: name,
    members: Table[MapKey, Value](),
  )

proc new_namespace*(parent: Namespace, name: string): Namespace =
  return Namespace(
    parent: parent,
    name: name,
    members: Table[MapKey, Value](),
  )

proc root*(self: Namespace): Namespace =
  if self.name == "<root>":
    return self
  else:
    return self.parent.root

proc has_key*(self: Namespace, key: MapKey): bool {.inline.} =
  return self.members.has_key(key)

proc `[]`*(self: Namespace, key: MapKey): Value {.inline.} =
  if self.has_key(key):
    return self.members[key]
  elif not self.stop_inheritance and self.parent != nil:
    return self.parent[key]
  else:
    raise new_exception(NotDefinedException, %key & " is not defined")

proc locate*(self: Namespace, key: MapKey): (Value, Namespace) {.inline.} =
  if self.has_key(key):
    result = (self.members[key], self)
  elif not self.stop_inheritance and self.parent != nil:
    result = self.parent.locate(key)
  else:
    not_allowed()

proc `[]`*(self: Namespace, key: string): Value {.inline.} =
  result = self[key.to_key]

proc `[]=`*(self: var Namespace, key: MapKey, val: Value) {.inline.} =
  self.members[key] = val

proc `[]=`*(self: var Namespace, key: string, val: Value) {.inline.} =
  self.members[key.to_key] = val

#################### Scope #######################

proc new_scope*(): Scope = Scope(
  members: @[],
  mappings: Table[MapKey, int](),
  mapping_history: @[],
)

proc max*(self: Scope): NameIndexScope {.inline.} =
  return self.members.len

proc set_parent*(self: var Scope, parent: Scope, max: NameIndexScope) {.inline.} =
  self.parent = parent
  self.parent_index_max = max

proc reset*(self: var Scope) {.inline.} =
  self.parent = nil
  self.members.setLen(0)

proc has_key(self: Scope, key: MapKey, max: int): bool {.inline.} =
  if self.mappings.has_key(key):
    var found = self.mappings[key]
    if found < max:
      return true
    if found > 255:
      var index = found and 0xFF
      if index < max:
        return true
      var history_index = found.shr(8) - 1
      var history = self.mapping_history[history_index]
      # If first >= max, all others will be >= max
      if history[0] < max:
        return true

  if self.parent != nil:
    return self.parent.has_key(key, self.parent_index_max)

proc has_key*(self: Scope, key: MapKey): bool {.inline.} =
  if self.mappings.has_key(key):
    return true
  elif self.parent != nil:
    return self.parent.has_key(key, self.parent_index_max)

proc def_member*(self: var Scope, key: MapKey, val: Value) {.inline.} =
  var index = self.members.len
  self.members.add(val)
  if self.mappings.has_key_or_put(key, index):
    var cur = self.mappings[key]
    if cur > 255:
      var history_index = cur.shr(8) - 1
      self.mapping_history[history_index].add(cur and 0xFF)
      self.mappings[key] = cur and 0b1111111100000000 + index
    else:
      var history_index = self.mapping_history.len
      self.mappings[key] = (history_index + 1).shl(8) + index

proc `[]`(self: Scope, key: MapKey, max: int): Value {.inline.} =
  if self.mappings.has_key(key):
    var found = self.mappings[key]
    if found > 255:
      var cur = found and 0xFF
      if cur < max:
        return self.members[cur]
      else:
        var history_index = found.shr(8) - 1
        var history = self.mapping_history[history_index]
        var i = history.len - 1
        while i >= 0:
          var index: int = history[i]
          if index < max:
            return self.members[index]
          i -= 1
    elif found < max:
      return self.members[found.int]

  if self.parent != nil:
    return self.parent[key, self.parent_index_max]

proc `[]`*(self: Scope, key: MapKey): Value {.inline.} =
  if self.mappings.has_key(key):
    return self.members[self.mappings[key].int]
  elif self.parent != nil:
    return self.parent[key, self.parent_index_max]

proc `[]=`(self: var Scope, key: MapKey, val: Value, max: int) {.inline.} =
  if self.mappings.has_key(key):
    var found = self.mappings[key]
    if found > 255:
      var index = found and 0xFF
      if index < max:
        self.members[index] = val
      else:
        var history_index = found.shr(8) - 1
        var history = self.mapping_history[history_index]
        var i = history.len - 1
        while i >= 0:
          var index: int = history[history_index]
          if index < max:
            self.members[index] = val
          i -= 1
    elif found < max:
      self.members[found.int] = val


  if self.parent != nil:
    self.parent.`[]=`(key, val, self.parent_index_max)
  else:
    not_allowed()

proc `[]=`*(self: var Scope, key: MapKey, val: Value) {.inline.} =
  if self.mappings.has_key(key):
    self.members[self.mappings[key].int] = val
  elif self.parent != nil:
    self.parent.`[]=`(key, val, self.parent_index_max)
  else:
    not_allowed()

#################### Frame #######################

proc new_frame*(): Frame = Frame(
  self: Nil,
)

proc reset*(self: var Frame) {.inline.} =
  self.self = nil
  self.ns = nil
  self.scope = nil
  self.extra = nil

proc `[]`*(self: Frame, name: MapKey): Value {.inline.} =
  result = self.scope[name]
  if result == nil:
    return self.ns[name]

proc `[]`*(self: Frame, name: Value): Value {.inline.} =
  case name.kind:
  of VkSymbol:
    result = self[name.symbol.to_key]
  of VkComplexSymbol:
    var csymbol = name.csymbol
    if csymbol[0] == "global":
      # result = VM.app.ns
      todo()
    elif csymbol[0] == "gene":
      result = VM.gene_ns
    elif csymbol[0] == "genex":
      result = VM.genex_ns
    elif csymbol[0] == "":
      # result = self.ns
      todo()
    else:
      result = self[csymbol[0].to_key]
    for csymbol in csymbol[1..^1]:
      # result = result.get_member(csymbol)
      todo()
  else:
    todo()

#################### Function ####################

proc new_fn*(name: string, matcher: RootMatcher, body: seq[Value]): Function =
  return Function(
    name: name,
    matcher: matcher,
    matching_hint: matcher.hint,
    body: body,
  )

#################### Macro #######################

proc new_macro*(name: string, matcher: RootMatcher, body: seq[Value]): Macro =
  return Macro(
    name: name,
    matcher: matcher,
    body: body,
  )

#################### Block #######################

proc new_block*(matcher: RootMatcher,  body: seq[Value]): Block =
  return Block(matcher: matcher, body: body)

#################### Return ######################

proc new_return*(): Return =
  return Return()

#################### Class #######################

proc new_class*(name: string): Class =
  return Class(
    name: name,
    ns: new_namespace(nil, name),
  )

proc get_method*(self: Class, name: MapKey): Method =
  if self.methods.has_key(name):
    return self.methods[name]
  elif self.parent != nil:
    return self.parent.get_method(name)

#################### Method ######################

proc new_method*(class: Class, name: string, fn: Function): Method =
  return Method(
    class: class,
    name: name,
    fn: fn,
  )

#################### ComplexSymbol ###############

proc all*(self: ComplexSymbol): seq[string] =
  result = @[self.first]
  for name in self.rest:
    result.add(name)

proc last*(self: ComplexSymbol): string =
  return self.rest[^1]

proc `==`*(this, that: ComplexSymbol): bool =
  return this.first == that.first and this.rest == that.rest

#################### Enum ########################

proc new_enum*(name: string): Enum =
  return Enum(name: name)

proc `[]`*(self: Enum, name: string): Value =
  # return new_gene_internal(self.members[name])
  todo()

proc add_member*(self: var Enum, name: string, value: int) =
  self.members[name] = EnumMember(parent: self, name: name, value: value)

proc `==`*(this, that: EnumMember): bool =
  return this.parent == that.parent and this.name == that.name

#################### Time ####################

proc `==`*(this, that: Time): bool =
  return this.hour == that.hour and
    this.minute == that.minute and
    this.second == that.second and
    this.timezone == that.timezone

#################### Value ###################

proc symbol_or_str*(self: Value): string =
  case self.kind:
  of VkSymbol:
    return self.symbol
  of VkString:
    return self.str
  else:
    not_allowed()

# proc get_member*(self: Value, name: string): Value =
#   case self.kind:
#   of VkInternal:
#     case self.internal.kind:
#     of VkNamespace:
#       return self.internal.ns[name.to_key]
#     of VkClass:
#       return self.internal.class.ns[name.to_key]
#     of VkEnum:
#       return self.internal.enum[name]
#     of VkEnumMember:
#       case name:
#       of "parent":
#         return self.internal.enum_member.parent
#       of "name":
#         return self.internal.enum_member.name
#       of "value":
#         return self.internal.enum_member.value
#       else:
#         not_allowed()
#     else:
#       todo()
#   else:
#     todo()

proc table_equals*(this, that: OrderedTable): bool =
  return this.len == 0 and that.len == 0 or
    this.len > 0 and that.len > 0 and this == that

proc `==`*(this, that: Value): bool =
  if this.is_nil:
    if that.is_nil: return true
    return false
  elif that.is_nil or this.kind != that.kind:
    return false
  else:
    case this.kind
    of VkAny:
      return this.any == that.any
    of VkNil, VkPlaceholder:
      return true
    of VkBool:
      return this.bool == that.bool
    of VkChar:
      return this.char == that.char
    of VkInt:
      return this.int == that.int
    of VkRatio:
      return this.ratio_num == that.ratio_num and this.ratio_denom == that.ratio_denom
    of VkFloat:
      return this.float == that.float
    of VkString:
      return this.str == that.str
    of VkSymbol:
      return this.symbol == that.symbol
    of VkComplexSymbol:
      return this.csymbol == that.csymbol
    of VkDate, VkDateTime:
      return this.date == that.date
    of VkTimeKind:
      return this.time == that.time
    of VkTimezone:
      return this.timezone == that.timezone
    of VkSet:
      return this.set.len == that.set.len and (this.set.len == 0 or this.set == that.set)
    of VkGene:
      return this.gene_type == that.gene_type and
        this.gene_data == that.gene_data and
        table_equals(this.gene_props, that.gene_props)
    of VkMap:
      return table_equals(this.map, that.map)
    of VkVector:
      return this.vec == that.vec
    of VkStream:
      return this.stream == that.stream
    of VkRegex:
      return this.regex == that.regex
    of VkRange:
      return this.range_start      == that.range_start      and
             this.range_end        == that.range_end        and
             this.range_incl_start == that.range_incl_start and
             this.range_incl_end   == that.range_incl_end
    else:
      todo($this.kind)

proc hash*(node: Value): Hash =
  var h: Hash = 0
  h = h !& hash(node.kind)
  case node.kind
  of VkNil, VkPlaceholder:
    discard
  of VkBool:
    h = h !& hash(node.bool)
  of VkChar:
    h = h !& hash(node.char)
  of VkInt:
    h = h !& hash(node.int)
  of VkRatio:
    h = h !& hash(node.ratio_num)
    h = h !& hash(node.ratio_denom)
  of VkFloat:
    h = h !& hash(node.float)
  of VkString:
    h = h !& hash(node.str)
  of VkSymbol:
    h = h !& hash(node.symbol)
  of VkComplexSymbol:
    h = h !& hash(node.csymbol[0] & "/" & node.csymbol[0].join("/"))
  of VkDate, VkDateTime:
    todo($node.kind)
  of VkTimeKind:
    todo($node.kind)
  of VkTimezone:
    todo($node.kind)
  of VkSet:
    h = h !& hash(node.set)
  of VkGene:
    if node.gene_type != nil:
      h = h !& hash(node.gene_type)
    h = h !& hash(node.gene_data)
  of VkMap:
    for key, val in node.map:
      h = h !& hash(key)
      h = h !& hash(val)
  of VkVector:
    h = h !& hash(node.vec)
  of VkStream:
    h = h !& hash(node.stream)
  of VkRegex:
    todo()
  of VkRange:
    h = h !& hash(node.range_start) !& hash(node.range_end)
  else:
    todo($node.kind)
  result = !$h

proc is_literal*(self: Value): bool =
  case self.kind:
  of VkBool, VkNil, VkInt, VkFloat, VkRatio:
    return true
  else:
    return false

proc `$`*(node: Value): string =
  if node.isNil:
    return "nil"
  case node.kind
  of VkNil:
    result = "nil"
  of VkBool:
    result = $(node.bool)
  of VkInt:
    result = $(node.int)
  of VkFloat:
    result = $(node.float)
  of VkString:
    result = "\"" & node.str.replace("\"", "\\\"") & "\""
  of VkSymbol:
    result = node.symbol
  of VkComplexSymbol:
    if node.csymbol[0] == "":
      result = "/" & node.csymbol[1..^1].join("/")
    else:
      result = node.csymbol[0] & "/" & node.csymbol[1..^1].join("/")
  of VkDate:
    result = node.date.format("yyyy-MM-dd")
  of VkDateTime:
    result = node.date.format("yyyy-MM-dd'T'HH:mm:sszzz")
  of VkTimeKind:
    result = &"{node.time.hour:02}:{node.time.minute:02}:{node.time.second:02}"
  of VkVector:
    result = "["
    result &= node.vec.join(" ")
    result &= "]"
  of VkGene:
    result = "(" & $node.gene_type
    if node.gene_props.len > 0:
      for k, v in node.gene_props:
        result &= " ^" & k.to_s & " " & $v
    if node.gene_data.len > 0:
      result &= " " & node.gene_data.join(" ")
    result &= ")"
  # of VkFunction:
  #   result = "(fn $# ...)" % [node.fn.name]
  # of VkMacro:
  #   result = "(macro $# ...)" % [node.mac.name]
  # of VkNamespace:
  #   result = "(ns $# ...)" % [node.ns.name]
  # of VkClass:
  #   result = "(class $# ...)" % [node.class.name]
  # of VkInstance:
  #   result = "($# ...)" % [node.instance.class.name]
  else:
    result = $node.kind

proc to_s*(self: Value): string =
  return case self.kind:
    of VkNil: ""
    of VkString: self.str
    else: $self

proc `%`*(self: Value): JsonNode =
  case self.kind:
  of VkNil:
    return newJNull()
  of VkBool:
    return %self.bool
  of VkInt:
    return %self.int
  of VkString:
    return %self.str
  of VkVector:
    result= newJArray()
    for item in self.vec:
      result.add(%item)
  of VkMap:
    result = newJObject()
    for k, v in self.map:
      result[k.to_s] = %v
  else:
    todo($self.kind)

proc to_json*(self: Value): string =
  return $(%self)

proc `[]`*(self: OrderedTable[MapKey, Value], key: string): Value =
  self[key.to_key]

proc `[]=`*(self: var OrderedTable[MapKey, Value], key: string, value: Value) =
  self[key.to_key] = value

#################### Constructors ################

proc new_gene_any*(v: pointer): Value =
  return Value(kind: VkAny, any: v)

proc new_gene_any*(v: pointer, `type`: MapKey): Value =
  return Value(kind: VkAny, any: v, any_type: `type`)

proc new_gene_any*(v: pointer, `type`: string): Value =
  return Value(kind: VkAny, any: v, any_type: `type`.to_key)

proc new_gene_string*(s: string): Value {.gcsafe.} =
  return Value(kind: VkString, str: s)

proc new_gene_string_move*(s: string): Value =
  result = Value(kind: VkString)
  shallowCopy(result.str, s)

proc new_gene_int*(s: string): Value =
  return Value(kind: VkInt, int: parseBiggestInt(s))

proc new_gene_int*(val: BiggestInt): Value =
  # return Value(kind: VkInt, int: val)
  if val > 100 or val < -10:
    return Value(kind: VkInt, int: val)
  else:
    return Ints[val + 10]

proc new_gene_ratio*(num, denom: BiggestInt): Value =
  return Value(kind: VkRatio, ratio_num: num, ratio_denom: denom)

proc new_gene_float*(s: string): Value =
  return Value(kind: VkFloat, float: parseFloat(s))

proc new_gene_float*(val: float): Value =
  return Value(kind: VkFloat, float: val)

proc new_gene_bool*(val: bool): Value =
  case val
  of true: return True
  of false: return False
  # of true: return Value(kind: VkBool, boolVal: true)
  # of false: return Value(kind: VkBool, boolVal: false)

proc new_gene_bool*(s: string): Value =
  let parsed: bool = parseBool(s)
  return new_gene_bool(parsed)

proc new_gene_char*(c: char): Value =
  return Value(kind: VkChar, char: c)

proc new_gene_char*(c: Rune): Value =
  return Value(kind: VkChar, rune: c)

proc new_gene_symbol*(name: string): Value =
  return Value(kind: VkSymbol, symbol: name)

proc new_gene_complex_symbol*(strs: seq[string]): Value =
  return Value(kind: VkComplexSymbol, csymbol: strs)

proc new_gene_regex*(regex: string, flags: set[RegexFlag] = {reStudy}): Value =
  return Value(kind: VkRegex, regex: re(regex, flags))

proc new_gene_range*(rstart: Value, rend: Value): Value =
  return Value(
    kind: VkRange,
    range_start: rstart,
    range_end: rend,
    range_incl_start: true,
    range_incl_end: false,
  )

proc new_gene_date*(year, month, day: int): Value =
  return Value(
    kind: VkDate,
    date_internal: DateTimeInternal(data: init_date_time(day, cast[Month](month), year, 0, 0, 0, utc())),
  )

proc new_gene_date*(date: DateTime): Value =
  return Value(
    kind: VkDate,
    date_internal: DateTimeInternal(data: date),
  )

proc new_gene_datetime*(date: DateTime): Value =
  return Value(
    kind: VkDateTime,
    date_internal: DateTimeInternal(data: date),
  )

proc new_gene_time*(hour, min, sec: int): Value =
  return Value(
    kind: VkTimeKind,
    time: Time(hour: hour, minute: min, second: sec, timezone: utc()),
  )

proc new_gene_vec*(items: seq[Value]): Value {.gcsafe.} =
  return Value(
    kind: VkVector,
    vec: items,
  )

proc new_gene_vec*(items: varargs[Value]): Value = new_gene_vec(@items)

proc new_gene_stream*(items: seq[Value]): Value =
  return Value(
    kind: VkStream,
    stream: items,
  )

proc new_gene_map*(): Value =
  return Value(
    kind: VkMap,
    map: OrderedTable[MapKey, Value](),
  )

converter new_gene_map*(self: OrderedTable[string, Value]): Value =
  return Value(
    kind: VkMap,
    map: self,
  )

proc new_gene_set*(items: varargs[Value]): Value =
  result = Value(
    kind: VkSet,
    set: OrderedSet[Value](),
  )
  for item in items:
    result.set.incl(item)

proc new_gene_map*(map: OrderedTable[MapKey, Value]): Value =
  return Value(
    kind: VkMap,
    map: map,
  )

proc new_gene_gene*(): Value =
  return Value(
    kind: VkGene,
    gene_type: Nil,
  )

proc new_gene_gene*(`type`: Value, data: varargs[Value]): Value =
  return Value(
    kind: VkGene,
    gene_type: `type`,
    gene_data: @data,
  )

proc new_gene_gene*(`type`: Value, props: OrderedTable[MapKey, Value], data: varargs[Value]): Value =
  return Value(
    kind: VkGene,
    gene_type: `type`,
    gene_props: props,
    gene_data: @data,
  )

proc new_mixin*(name: string): Mixin =
  return Mixin(name: name)

proc new_instance*(class: Class): Instance =
  return Instance(value: new_gene_gene(), class: class)

# Do not allow auto conversion between CatchableError and Value
# because there are sub-classes of CatchableError that need to be
# handled differently.
proc error_to_gene*(ex: ref CatchableError): Value =
  return Value(
    kind: VkException,
    # exception: ex,
  )

proc new_gene_explode*(v: Value): Value =
  return Value(
    kind: VkExplode,
    # explode: v,
  )

#################### Value ###################

proc is_truthy*(self: Value): bool =
  case self.kind:
  of VkBool:
    return self.bool
  of VkNil:
    return false
  else:
    return true

proc merge*(self: var Value, value: Value) =
  case self.kind:
  of VkGene:
    case value.kind:
    of VkGene:
      for item in value.gene_data:
        self.gene_data.add(item)
      for k, v in value.gene_props:
        self.gene_props[k] = v
    of VkVector:
      for item in value.vec:
        self.gene_data.add(item)
    of VkMap:
      for k, v in value.map:
        self.gene_props[k] = v
    else:
      todo()
  of VkVector:
    case value.kind:
    of VkVector:
      for item in value.vec:
        self.gene_data.add(item)
    else:
      todo()
  else:
    todo()

#################### Document ####################

proc new_doc*(data: seq[Value]): Document =
  return Document(data: data)

#################### Converters ##################

converter to_gene*(v: int): Value                      = new_gene_int(v)
converter to_gene*(v: bool): Value                     = new_gene_bool(v)
converter to_gene*(v: float): Value                    = new_gene_float(v)
converter to_gene*(v: string): Value                   = new_gene_string(v)
converter to_gene*(v: char): Value                     = new_gene_char(v)
converter to_gene*(v: Rune): Value                     = new_gene_char(v)
converter to_gene*(v: OrderedTable[MapKey, Value]): Value = new_gene_map(v)

# Below converter causes problem with the hash function
# converter to_gene*(v: seq[Value]): Value           = new_gene_vec(v)

converter to_bool*(v: Value): bool =
  if v.isNil:
    return false
  case v.kind:
  of VkNil:
    return false
  of VkBool:
    return v.bool
  of VkString:
    return v.str != ""
  else:
    return true

proc wrap_with_try*(body: seq[Value]): seq[Value] =
  var found_catch_or_finally = false
  for item in body:
    if item == Catch or item == Finally:
      found_catch_or_finally = true
  if found_catch_or_finally:
    return @[new_gene_gene(Try, body)]
  else:
    return body

converter to_macro*(node: Value): Macro =
  var first = node.gene_data[0]
  var name: string
  if first.kind == VkSymbol:
    name = first.symbol
  elif first.kind == VkComplexSymbol:
    name = first.csymbol[^1]

  var matcher = new_arg_matcher()
  matcher.parse(node.gene_data[1])

  var body: seq[Value] = @[]
  for i in 2..<node.gene_data.len:
    body.add node.gene_data[i]

  body = wrap_with_try(body)
  return new_macro(name, matcher, body)

converter to_block*(node: Value): Block =
  var matcher = new_arg_matcher()
  if node.gene_props.has_key(ARGS_KEY):
    matcher.parse(node.gene_props[ARGS_KEY])
  var body: seq[Value] = @[]
  for i in 0..<node.gene_data.len:
    body.add node.gene_data[i]

  body = wrap_with_try(body)
  return new_block(matcher, body)

converter json_to_gene*(node: JsonNode): Value =
  case node.kind:
  of JNull:
    return Nil
  of JBool:
    return node.bval
  of JInt:
    return node.num
  of JFloat:
    return node.fnum
  of JString:
    return node.str
  of JObject:
    result = new_gene_map()
    for k, v in node.fields:
      result.map[k.to_key] = v.json_to_gene
  of JArray:
    result = new_gene_vec()
    for elem in node.elems:
      result.vec.add(elem.json_to_gene)

#################### Pattern Matching ############

proc new_match_matcher*(): RootMatcher =
  result = RootMatcher(
    mode: MatchExpression,
  )

proc new_arg_matcher*(): RootMatcher =
  result = RootMatcher(
    mode: MatchArgParsing,
  )

proc new_matcher(root: RootMatcher, kind: MatcherKind): Matcher =
  result = Matcher(
    root: root,
    kind: kind,
  )

proc hint*(self: RootMatcher): MatchingHint =
  if self.children.len == 0:
    result.mode = MhNone
  else:
    result.mode = MhSimpleData

proc new_matched_field(name: MapKey, value: Value): MatchedField =
  result = MatchedField(
    name: name,
    value: value,
  )

proc required(self: Matcher): bool =
  return self.default_value == nil and not self.splat

proc props(self: seq[Matcher]): HashSet[MapKey] =
  for m in self:
    if m.kind == MatchProp and not m.splat:
      result.incl(m.name)

proc prop_splat(self: seq[Matcher]): MapKey =
  for m in self:
    if m.kind == MatchProp and m.splat:
      return m.name

#################### Parsing #####################

proc calc_min_left*(self: var Matcher) =
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    var m = self.children[i]
    m.min_left = min_left
    if m.required:
      min_left += 1

proc calc_min_left*(self: var RootMatcher) =
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    var m = self.children[i]
    m.calc_min_left
    m.min_left = min_left
    if m.required:
      min_left += 1

proc parse(self: var RootMatcher, group: var seq[Matcher], v: Value) =
  case v.kind:
  of VkSymbol:
    if v.symbol[0] == '^':
      var m = new_matcher(self, MatchProp)
      if v.symbol.ends_with("..."):
        m.name = v.symbol[1..^4].to_key
        m.splat = true
      else:
        m.name = v.symbol[1..^1].to_key
      group.add(m)
    else:
      var m = new_matcher(self, MatchData)
      group.add(m)
      if v.symbol != "_":
        if v.symbol.endsWith("..."):
          m.name = v.symbol[0..^4].to_key
          m.splat = true
        else:
          m.name = v.symbol.to_key
  of VkVector:
    var i = 0
    while i < v.vec.len:
      var item = v.vec[i]
      i += 1
      if item.kind == VkVector:
        var m = new_matcher(self, MatchData)
        group.add(m)
        self.parse(m.children, item)
      else:
        self.parse(group, item)
        if i < v.vec.len and v.vec[i] == new_gene_symbol("="):
          i += 1
          var last_matcher = group[^1]
          var value = v.vec[i]
          i += 1
          last_matcher.default_value = value
  else:
    todo()

proc parse*(self: var RootMatcher, v: Value) =
  if v == new_gene_symbol("_"):
    return
  self.parse(self.children, v)
  self.calc_min_left

#################### Matching ####################

proc `[]`*(self: Value, i: int): Value =
  case self.kind:
  of VkGene:
    return self.gene_data[i]
  of VkVector:
    return self.vec[i]
  else:
    not_allowed()

proc `len`(self: Value): int =
  if self == nil:
    return 0
  case self.kind:
  of VkGene:
    return self.gene_data.len
  of VkVector:
    return self.vec.len
  else:
    not_allowed()

proc match_prop_splat*(self: seq[Matcher], input: Value, r: MatchResult) =
  if input == nil or self.prop_splat == EMPTY_STRING_KEY:
    return

  var map: OrderedTable[MapKey, Value]
  case input.kind:
  of VkMap:
    map = input.map
  of VkGene:
    map = input.gene_props
  else:
    return

  var splat = OrderedTable[MapKey, Value]()
  for k, v in map:
    if k notin self.props:
      splat[k] = v
  r.fields.add(new_matched_field(self.prop_splat, new_gene_map(splat)))

proc match(self: Matcher, input: Value, state: MatchState, r: MatchResult) =
  case self.kind:
  of MatchData:
    var value: Value
    var value_expr: Expr
    if self.splat:
      value = new_gene_vec()
      for i in state.data_index..<input.len - self.min_left:
        value.vec.add(input[i])
        state.data_index += 1
    elif self.min_left < input.len - state.data_index:
      value = input[state.data_index]
      state.data_index += 1
    else:
      if self.default_value == nil:
        r.kind = MatchMissingFields
        r.missing.add(self.name)
        return
      elif self.default_value_expr != nil:
        value_expr = self.default_value_expr
      else:
        value = self.default_value # Default value
    if self.name != EMPTY_STRING_KEY:
      var matched_field = new_matched_field(self.name, value)
      matched_field.value_expr = value_expr
      r.fields.add(matched_field)
    var child_state = MatchState()
    for child in self.children:
      child.match(value, child_state, r)
    match_prop_splat(self.children, value, r)
  of MatchProp:
    var value: Value
    var value_expr: Expr
    if self.splat:
      return
    elif input.gene_props.has_key(self.name):
      value = input.gene_props[self.name]
    else:
      if self.default_value == nil:
        r.kind = MatchMissingFields
        r.missing.add(self.name)
        return
      elif self.default_value_expr != nil:
        value_expr = self.default_value_expr
      else:
        value = self.default_value # Default value
    var matched_field = new_matched_field(self.name, value)
    matched_field.value_expr = value_expr
    r.fields.add(matched_field)
  else:
    todo()

proc match*(self: RootMatcher, input: Value): MatchResult =
  result = MatchResult()
  var children = self.children
  var state = MatchState()
  for child in children:
    child.match(input, state, result)
  match_prop_splat(children, input, result)

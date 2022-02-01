import os, nre, strutils, tables, unicode, hashes, sets, asyncdispatch, times, strformat
import macros

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
  Evaluator* = proc(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value

  NativeFn* = proc(args: Value): Value
  NativeMethod* = proc(self: Value, args: Value): Value

  # NativeMacro is similar to NativeMethod, but args are not evaluated before passed in
  # To distinguish NativeMacro and NativeMethod, we just create Value with different kind
  # (i.e. VkNativeMacro vs VkNativeMethod)
  # NativeMacro* = proc(self: Value, args: Value): Value

  GeneProcessor* = ref object of RootObj
    translator*: Translator

  Runtime* = ref object
    name*: string     # default/...
    home*: string     # GENE_HOME directory
    version*: string
    # features*: Table[string, Feature]
    props*: Table[string, Value]  # Additional properties

  # It might not be very useful to group functionalities by features
  # because we can not easily disable features.
  # Instead we should define capabilities, e.g. file system access,
  # network access, environment access, input/output device access etc.
  # Capabilities can be enabled/disabled on application, package, module level.

  # # To group functionality like oop, macro, repl
  # # Features should be divided into core features (e.g. if, var, namespace etc)
  # # and non-core features (e.g. repl etc)
  # Feature* = ref object
  #   parent*: Feature
  #   key*: string                  # E.g. oop
  #   name*: string                 # E.g. Object Oriented Programming
  #   description*: string          # E.g. More descriptive information about the feature
  #   props*: Table[string, Value]  # Additional properties
  #   children*: Table[string, Feature]

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
    doc*: Document        # content of package.gene

  Module* = ref object
    pkg*: Package         # Package in which the module belongs, or stdlib if not set
    name*: string
    ns*: Namespace
    props*: Table[string, Value]  # Additional properties
    reloadable*: bool

  Namespace* = ref object
    module*: Module
    parent*: Namespace
    is_root*: bool           # is the root namespace of a module
    stop_inheritance*: bool  # When set to true, stop looking up for members
    name*: string
    members*: Table[MapKey, Value]
    member_missing*: Value

  Reloadable* = ref object
    module*: Module
    path*: seq[MapKey]

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
    constructor*: Method
    methods*: Table[MapKey, Method]
    # method_missing*: Value
    ns*: Namespace # Class can act like a namespace

  Mixin* = ref object
    name*: string
    methods*: Table[MapKey, Method]
    ns*: Namespace # Mixin can act like a namespace

  Method* = ref object
    class*: Class
    name*: string
    callable*: Value
    # public*: bool

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
    ns*: Namespace
    parent_scope*: Scope
    parent_scope_max*: NameIndexScope
    matcher*: RootMatcher
    matching_hint*: MatchingHint
    body*: seq[Value]
    body_compiled*: Expr

  Macro* = ref object of GeneProcessor
    ns*: Namespace
    parent_scope*: Scope
    parent_scope_max*: NameIndexScope
    name*: string
    matcher*: RootMatcher
    matching_hint*: MatchingHint
    body*: seq[Value]
    body_compiled*: Expr

  Enum* = ref object
    name*: string
    members*: OrderedTable[string, EnumMember]

  EnumMember* = ref object
    parent*: Enum
    name*: string
    value*: int

  # applicable to numbers, characters
  Range* = ref object
    start*: Value
    `end`*: Value
    step*: Value # default to 1 if first is greater than last
    # include_start*: bool # always true
    include_end*: bool # default to false

  RegexFlag* = enum
    RfIgnoreCase
    RfMultiLine
    RfDotAll      # Nim nre: (?s) - . also matches newline (dotall)
    RfExtended    # Nim nre: (?x) - whitespace and comments (#) are ignored (extended)

  # Non-date specific time object
  Time* = ref object
    hour*: int
    minute*: int
    second*: int
    nanosec*: int
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
    VkRegexMatch
    VkRange
    VkSelector
    VkCast
    VkQuote
    VkUnquote
    # Time part should be 00:00:00 and timezone should not matter
    VkDate
    # Date + time + timezone
    VkDateTime
    VkTime
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
    VkFuture
    VkExpr
    VkGeneProcessor
    VkApplication
    VkPackage
    VkModule
    VkNamespace
    VkReloadable
    VkFunction
    VkMacro
    VkBlock
    VkReturn
    VkClass
    VkMixin
    VkMethod
    VkNativeFn
    VkNativeMethod
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
      regex_pattern*: string
      regex_flags: set[RegexFlag]
    of VkRegexMatch:
      regex_match*: RegexMatch
    of VkRange:
      range*: Range
    of VkDate, VkDateTime:
      date_internal: DateTimeInternal
    of VkTime:
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
    of VkEnum:
      `enum`*: Enum
    of VkEnumMember:
      `enum_member`*: EnumMember
    of VkStream:
      stream*: seq[Value]
    of VkQuote:
      quote*: Value
    of VkUnquote:
      unquote*: Value
      unquote_discard*: bool
    of VkExplode:
      explode*: Value
    of VkSelector:
      selector*: Selector
    of VkCast:
      cast_class*: Class
      cast_value*: Value
    # Internal types
    of VkException:
      exception*: ref CatchableError
    of VkFuture:
      future*: Future[Value]
      ft_success_callbacks*: seq[Value]
      ft_failure_callbacks*: seq[Value]
    of VkExpr:
      expr*: Expr
    of VkGeneProcessor:
      gene_processor*: GeneProcessor
    of VkApplication:
      app*: Application
    of VkNamespace:
      ns*: Namespace
    of VkReloadable:
      reloadable*: Reloadable
    of VkFunction:
      fn*: Function
    of VkMacro:
      `macro`*: Macro
    of VkBlock:
      `block`*: Block
    of VkClass:
      class*: Class
    of VkMixin:
      `mixin`*: Mixin
    of VkMethod:
      `method`*: Method
    of VkNativeFn:
      native_fn*: NativeFn
    of VkNativeMethod:
      native_method*: NativeMethod
    of VkInstance:
      instance_class*: Class
      instance_props*: Table[MapKey, Value]
    of VkFile:
      file*: File
    else:
      discard

  Expr* = ref object of RootObj
    evaluator*: Evaluator

  CustomValue* = ref object of RootObj

  Document* = ref object
    `type`: Value
    props*: OrderedTable[MapKey, Value]
    data*: seq[Value]

  # environment: local/unittest/development/staging/production
  # assertion: enabled/disabled
  # log level: fatal/error/warning/info/debug/trace
  # repl on error: true/false
  # capabilities:
  #   environment variables: read/write
  #   stdin/stdout/stderr/pipe: read/write
  #   gui:
  #   file system: read/write
  #   os execution: read/write
  #   database: read/write
  #   socket client: read/write
  #   socket server:
  #   http: read/write
  #   custom capabilities provided by libraries

  VirtualMachineInternal = object
    app*: Application
    modules*: OrderedTable[MapKey, Module]
    repl_on_error*: bool

  VirtualMachine* = ptr VirtualMachineInternal

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
      `macro`*: Macro
    of FrMethod:
      `method`*: Method
    else:
      discard
    props*: Table[MapKey, Value]

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
    is_prop*: bool
    # match_name*: bool # Match symbol to name - useful for (myif true then ... else ...)
    # default_value*: Value
    default_value_expr*: Expr
    is_splat*: bool
    min_left*: int # Minimum number of args following this
    children*: seq[Matcher]
    # required*: bool # computed property: true if splat is false and default value is not given

  MatchResultKind* = enum
    MatchSuccess
    MatchMissingFields
    MatchWrongType # E.g. map is passed but array or gene is expected

  # MatchedField* = ref object
  #   matcher*: Matcher
  #   value*: Value

  MatchResult* = ref object
    message*: string
    kind*: MatchResultKind
    # If success
    # fields*: seq[MatchedField]
    # assign_only*: bool # If true, no new variables will be defined
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

  SelectorNoResult* = object of Exception

  Selector* {.acyclic.} = ref object of GeneProcessor
    children*: seq[SelectorItem]  # Each child represents a branch
    default*: Value

  SelectorItemKind* = enum
    SiDefault
    SiSelector

  SelectorItem* {.acyclic.} = ref object
    case kind*: SelectorItemKind
    of SiDefault:
      matchers*: seq[SelectorMatcher]
      children*: seq[SelectorItem]  # Each child represents a branch
    of SiSelector:
      selector*: Selector

  SelectorMatcherKind* = enum
    SmByIndex
    SmByIndexList
    SmByIndexRange
    SmByName
    SmByNameList
    SmByNamePattern
    SmSymbol
    SmByType
    SmType
    SmProps
    SmKeys
    SmValues
    SmData
    SmSelfAndDescendants
    SmDescendants
    SmCallback

  SelectorMatcher* = ref object
    root*: Selector
    case kind*: SelectorMatcherKind
    of SmByIndex:
      index*: int
    of SmByIndexRange:
      range*: Range
    of SmByName:
      name*: MapKey
    of SmByType:
      by_type*: Value
    of SmCallback:
      callback*: Value
    else: discard

  SelectResultMode* = enum
    SrFirst
    SrAll

  SelectorResult* = ref object
    done*: bool
    case mode*: SelectResultMode
    of SrFirst:
      first*: Value
    of SrAll:
      all*: seq[Value]

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
  Equals*    = Value(kind: VkSymbol, symbol: "=")

var VmCreatedCallbacks*: seq[proc(self: VirtualMachine)] = @[]

var Ints: array[111, Value]
for i in 0..110:
  Ints[i] = Value(kind: VkInt, int: i - 10)

var VM*: VirtualMachine   # The current virtual machine

var HotReloadListener*: Channel[string]
HotReloadListener.open()

var GLOBAL_NS*     : Value
var GENE_NS*       : Value
var GENE_NATIVE_NS*: Value
var GENEX_NS*      : Value

var ObjectClass*   : Value
var ClassClass*    : Value
var ExceptionClass*: Value
var FutureClass*   : Value
var NamespaceClass*: Value
var MixinClass*    : Value
var FunctionClass* : Value
var MacroClass*    : Value
var BlockClass*    : Value
var NilClass*      : Value
var BoolClass*     : Value
var IntClass*      : Value
var FloatClass*    : Value
var CharClass*     : Value
var StringClass*   : Value
var SymbolClass*   : Value
var ArrayClass*    : Value
var MapClass*      : Value
var StreamClass*   : Value
var SetClass*      : Value
var GeneClass*     : Value
var DocumentClass* : Value
var FileClass*     : Value
var DateClass*     : Value
var DatetimeClass* : Value
var TimeClass*     : Value
var SelectorClass* : Value

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

proc new_gene_processor*(translator: Translator): Value =
  return Value(
    kind: VkGeneProcessor,
    gene_processor: GeneProcessor(translator: translator),
  )

proc new_gene_future*(f: Future[Value]): Value =
  return Value(
    kind: VkFuture,
    future: f,
  )

proc date*(self: Value): DateTime =
  self.date_internal.data

# https://forum.nim-lang.org/t/8516#55153
macro name*(name: static string, f: untyped): untyped =
  f.expectKind(nnkLambda)
  result = nnkProcDef.newNimNode()
  f.copyChildrenTo(result)
  let id = ident(name)
  result[0] = id
  result = quote do:
    block:
      `result`
      `id`

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
    ns: new_namespace(VM.app.ns),
  )
  result.ns.module = result
  result.ns.is_root = true

proc new_module*(): Module =
  result = new_module("<unknown>")

proc new_module*(ns: Namespace, name: string): Module =
  result = Module(
    name: name,
    ns: new_namespace(ns),
  )
  result.ns.module = result
  result.ns.is_root = true

proc new_module*(ns: Namespace): Module =
  result = new_module(ns, "<unknown>")

#################### Namespace ###################

proc new_namespace*(): Namespace =
  return Namespace(
    name: "<root>",
    members: Table[MapKey, Value](),
  )

# assume anonymous namespace is the root, good idea?
proc new_namespace*(parent: Namespace): Namespace =
  return Namespace(
    module: parent.module,
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
  result = Namespace(
    parent: parent,
    name: name,
    members: Table[MapKey, Value](),
  )
  if parent != nil:
    result.module = parent.module

proc root*(self: Namespace): Namespace =
  if self.is_root:
    return self
  else:
    return self.parent.root

proc is_reloadable*(self: Namespace): bool =
  self.module != nil and self.module.reloadable

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
      self.mappings[key] = (cur and 0b1111111100000000) + index
    else:
      var history_index = self.mapping_history.len
      self.mapping_history.add(@[NameIndexScope(cur)])
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
    var found = self.mappings[key]
    if found > 255:
      found = found and 0xFF
    return self.members[found]
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

  elif self.parent != nil:
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
  # of VkComplexSymbol:
  #   var csymbol = name.csymbol
  #   if csymbol[0] == "global":
  #     # result = VM.app.ns
  #     todo()
  #   elif csymbol[0] == "gene":
  #     result = VM.gene_ns
  #   elif csymbol[0] == "genex":
  #     result = VM.genex_ns
  #   elif csymbol[0] == "":
  #     # result = self.ns
  #     todo()
  #   else:
  #     result = self[csymbol[0].to_key]
  #   for csymbol in csymbol[1..^1]:
  #     # result = result.get_member(csymbol)
  #     todo()
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
    matching_hint: matcher.hint,
    body: body,
  )

#################### Block #######################

proc new_block*(matcher: RootMatcher,  body: seq[Value]): Block =
  return Block(
    matcher: matcher,
    matching_hint: matcher.hint,
    body: body,
  )

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
  # else:
  #   not_allowed("No method available: " & name.to_s)

proc get_super_method*(self: Class, name: MapKey): Method =
  if self.parent != nil:
    return self.parent.get_method(name)
  else:
    not_allowed("No super method available: " & name.to_s)

proc get_class*(val: Value): Class =
  case val.kind:
  # of VkApplication:
  #   return VM.gene_ns.ns[APPLICATION_CLASS_KEY].class
  # of VkPackage:
  #   return VM.gene_ns.ns[PACKAGE_CLASS_KEY].class
  of VkInstance:
    return val.instance_class
  of VkCast:
    return val.cast_class
  of VkClass:
    return ClassClass.class
  of VkNamespace:
    return NamespaceClass.class
  of VkFuture:
    return FutureClass.class
  of VkFile:
    return FileClass.class
  of VkException:
    var ex = val.exception
    if ex is Exception:
      var ex = cast[Exception](ex)
      if ex.instance != nil:
        return ex.instance.instance_class
      else:
        return ExceptionClass.class
    # elif ex is CatchableError:
    #   var nim = VM.app.ns[NIM_KEY]
    #   return nim.ns[CATCHABLE_ERROR_KEY].class
    else:
      return ExceptionClass.class
  of VkNil:
    return NilClass.class
  of VkBool:
    return BoolClass.class
  of VkInt:
    return IntClass.class
  of VkChar:
    return CharClass.class
  of VkString:
    return StringClass.class
  of VkSymbol:
    return SymbolClass.class
  # of VkComplexSymbol:
  #   return ComplexSymbolClass.class
  of VkVector:
    return ArrayClass.class
  of VkMap:
    return MapClass.class
  of VkSet:
    return SetClass.class
  of VkGene:
    return GeneClass.class
  # of VkRegex:
  #   return VM.gene_ns.ns[REGEX_CLASS_KEY].class
  # of VkRange:
  #   return VM.gene_ns.ns[RANGE_CLASS_KEY].class
  of VkDate:
    return DateClass.class
  of VkDateTime:
    return DateTimeClass.class
  of VkTime:
    return TimeClass.class
  # of VkTimezone:
  #   return VM.gene_ns.ns[TIMEZONE_CLASS_KEY].class
  of VkAny:
    if val.any_type == HTTP_REQUEST_KEY:
      return GENEX_NS.ns[HTTP_KEY].ns[REQUEST_CLASS_KEY].class
    else:
      todo("get_class " & $val.kind)
  else:
    todo("get_class " & $val.kind)

proc is_a*(self: Value, class: Class): bool =
  var my_class = self.get_class
  while true:
    if my_class == class:
      return true
    if my_class.parent == nil:
      return false
    else:
      my_class = my_class.parent

#################### Method ######################

proc new_method*(class: Class, name: string, fn: Function): Method =
  return Method(
    class: class,
    name: name,
    callable: Value(kind: VkFunction, fn: fn),
  )

proc clone*(self: Method): Method =
  return Method(
    class: self.class,
    name: self.name,
    callable: self.callable,
  )

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

#################### Reloadable ##############

proc resolve*(self: Namespace, path: seq[MapKey], pos: int): Value =
  var key = path[pos]
  var val = self[key]
  if pos < path.len - 1:
    case val.kind:
    of VkNamespace:
      return val.ns.resolve(path, pos + 1)
    else:
      todo("resolve " & $val.kind)
  else:
    return val

proc resolve*(self: Reloadable): Value =
  self.module.ns.resolve(self.path, 0)

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

proc resolve*(self: Value): Value {.inline.} =
  if not self.is_nil and self.kind == VkReloadable:
    return self.reloadable.resolve()
  else:
    return self

proc `==`*(this, that: Value): bool =
  var this = this.resolve()
  var that = that.resolve()

  if this.is_nil:
    return that.is_nil
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
    of VkTime:
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
      return this.range == that.range
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
    h = h !& hash(node.csymbol.join("/"))
  of VkDate, VkDateTime:
    todo($node.kind)
  of VkTime:
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
    h = h !& hash(node.range.start) !& hash(node.range.end)
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
    result = node.csymbol.join("/")
  of VkDate:
    result = node.date.format("yyyy-MM-dd")
  of VkDateTime:
    result = node.date.format("yyyy-MM-dd'T'HH:mm:sszzz")
  of VkTime:
    result = &"{node.time.hour:02}:{node.time.minute:02}:{node.time.second:02}"
  of VkVector:
    result = "["
    result &= node.vec.join(" ")
    result &= "]"
  of VkMap:
    result = "{"
    var is_first = true
    for k, v in node.map:
      if is_first:
        is_first = false
      else:
        result &= " "
      result &= "^"
      result &= k.to_s
      result &= " "
      result &= $v
    result &= "}"
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
  Value(
    kind: VkComplexSymbol,
    csymbol: strs,
  )

proc new_gene_regex*(regex: string, flags: set[RegexFlag]): Value =
  var s = ""
  for flag in flags:
    case flag:
    of RfIgnoreCase:
      s &= "(?i)"
    of RfMultiLine:
      s &= "(?m)"
    else:
      todo($flag)
  s &= regex
  return Value(
    kind: VkRegex,
    regex: re(s),
    regex_pattern: regex,
    regex_flags: flags,
  )

proc new_gene_regex*(regex: string): Value =
  return Value(
    kind: VkRegex,
    regex: re(regex),
    regex_pattern: regex,
  )

proc new_gene_range*(start: Value, `end`: Value): Value =
  return Value(
    kind: VkRange,
    range: Range(start: start, `end`: `end`),
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
    kind: VkTime,
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

proc new_gene_map*(map: OrderedTable[MapKey, Value]): Value =
  return Value(
    kind: VkMap,
    map: map,
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

proc new_gene_enum_member*(m: EnumMember): Value =
  return Value(
    kind: VkEnumMember,
    enum_member: m,
  )

proc new_mixin*(name: string): Mixin =
  return Mixin(
    name: name,
    ns: new_namespace(nil, name),
  )

proc new_gene_reloadable*(module: Module, path: seq[MapKey]): Value =
  return Value(
    kind: VkReloadable,
    reloadable: Reloadable(module: module, path: path),
  )

# Do not allow auto conversion between CatchableError and Value
# because there are sub-classes of CatchableError that need to be
# handled differently.
proc error_to_gene*(ex: ref CatchableError): Value =
  return Value(
    kind: VkException,
    exception: ex,
  )

proc new_gene_explode*(v: Value): Value =
  return Value(
    kind: VkExplode,
    explode: v,
  )

proc new_gene_native_method*(meth: NativeMethod): Value =
  return Value(
    kind: VkNativeMethod,
    native_method: meth,
  )

proc new_gene_native_fn*(fn: NativeFn): Value =
  return Value(
    kind: VkNativeFn,
    native_fn: fn,
  )

converter new_gene_file*(file: File): Value =
  return Value(
    kind: VkFile,
    file: file,
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

# proc is_empty*(self: Value): bool =
#   case self.kind:
#   of VkNil:
#     return true
#   of VkVector:
#     return self.vec.len == 0
#   of VkMap:
#     return self.map.len == 0
#   of VkString:
#     return self.str.len == 0
#   else:
#     return false

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

#################### Selector ####################

proc new_gene_selector*(selector: Selector): Value =
  Value(kind: VkSelector, selector: selector)

proc new_selector*(): Selector =
  result = Selector()

proc gene_to_selector_item*(v: Value): SelectorItem =
  case v.kind:
  of VkSelector:
    result = SelectorItem(
      kind: SiSelector,
      selector: v.selector,
    )
  of VkFunction:
    result = SelectorItem()
    result.matchers.add(SelectorMatcher(kind: SmCallback, callback: v))
  of VkInt:
    result = SelectorItem()
    result.matchers.add(SelectorMatcher(kind: SmByIndex, index: v.int))
  of VkString:
    result = SelectorItem()
    result.matchers.add(SelectorMatcher(kind: SmByName, name: v.str.to_key))
  of VkSymbol:
    result = SelectorItem()
    result.matchers.add(SelectorMatcher(kind: SmByType, by_type: v))
  of VkPlaceholder:
    result = SelectorItem()
    result.matchers.add(SelectorMatcher(kind: SmSelfAndDescendants))
  of VkVector:
    result = SelectorItem()
    for item in v.vec:
      case item.kind:
      of VkInt:
        result.matchers.add(SelectorMatcher(kind: SmByIndex, index: item.int))
      of VkString:
        result.matchers.add(SelectorMatcher(kind: SmByName, name: item.str.to_key))
      of VkSymbol:
        result.matchers.add(SelectorMatcher(kind: SmByType, by_type: item))
      else:
        todo()
  of VkRange:
    result = SelectorItem()
    result.matchers.add(SelectorMatcher(kind: SmByIndexRange, range: v.range))
  else:
    todo($v.kind)

# Definition
proc is_singular*(self: Selector): bool

proc is_singular*(self: SelectorItem): bool =
  case self.kind:
  of SiDefault:
    if self.matchers.len > 1:
      return false
    if self.matchers[0].kind notin [SmByIndex, SmByName]:
      return false
    case self.children.len:
    of 0:
      return true
    of 1:
      return self.children[0].is_singular()
    else:
      return false
  of SiSelector:
    result = self.selector.is_singular()

proc is_singular*(self: Selector): bool =
  result = self.children.len == 1 and self.children[0].is_singular()

proc is_last*(self: SelectorItem): bool =
  result = self.children.len == 0

#################### Pattern Matching ############

proc new_match_matcher*(): RootMatcher =
  result = RootMatcher(
    mode: MatchExpression,
  )

proc new_arg_matcher*(): RootMatcher =
  result = RootMatcher(
    mode: MatchArgParsing,
  )

proc new_matcher*(root: RootMatcher, kind: MatcherKind): Matcher =
  result = Matcher(
    root: root,
    kind: kind,
  )

proc required*(self: Matcher): bool =
  return self.default_value_expr == nil and not self.is_splat

proc hint*(self: RootMatcher): MatchingHint =
  if self.children.len == 0:
    result.mode = MhNone
  else:
    result.mode = MhSimpleData
    for item in self.children:
      if item.kind != MatchData or not item.required:
        result.mode = MhDefault
        return

# proc new_matched_field*(name: MapKey, value: Value): MatchedField =
#   result = MatchedField(
#     name: name,
#     value: value,
#   )

proc props*(self: seq[Matcher]): HashSet[MapKey] =
  for m in self:
    if m.kind == MatchProp and not m.is_splat:
      result.incl(m.name)

proc prop_splat*(self: seq[Matcher]): MapKey =
  for m in self:
    if m.kind == MatchProp and m.is_splat:
      return m.name

#################### VirtualMachine ##############

proc new_virtual_machine*(): VirtualMachine =
  create(VirtualMachineInternal, sizeof(VirtualMachineInternal))

##################################################

import os, strutils, tables, unicode, hashes, sets, times, strformat, pathnorm
import nre
import asyncdispatch
import threadpool
import dynlib
import macros

const ASYNC_WAIT_LIMIT = 10
const DEFAULT_ERROR_MESSAGE = "Error occurred."

type
  RegexFlag* = enum
    RfIgnoreCase
    RfMultiLine
    RfDotAll      # Nim nre: (?s) - . also matches newline (dotall)
    RfExtended    # Nim nre: (?x) - whitespace and comments (#) are ignored (extended)

  ValueKind* = enum
    # VkVoid vs VkNil vs VkPlaceholder:
    #   VkVoid has special meaning in some places (e.g. templates)
    #   Value(kind: VkNil) and nil should have same meaning and is the default/uninitialized value.
    #   VkPlaceholder can be interpreted any way we want
    VkVoid
    VkNil
    VkPlaceholder
    # VkAny vs VkCustom:
    # VkAny can be used to represent anything
    # VkCustom can be used to represent any value that inherits from CustomValue
    VkAny
    VkCustom
    VkBool
    VkInt
    VkRatio
    VkFloat
    VkBin
    VkBin64
    VkByte
    VkBytes
    # VkPercent # xx.xx%
    VkChar
    VkString
    VkSymbol
    VkComplexSymbol
    VkRegex
    VkRegexMatch
    VkRange
    VkSelector
    VkQuote
    VkUnquote
    # Time part should be 00:00:00 and timezone should not matter
    VkDate
    # Date + time + timezone
    VkDateTime
    VkTime
    VkTimezone
    VkVector
    VkMap
    VkSet
    VkGene
    VkStream
    VkDocument
    VkFile
    VkArchiveFile
    VkDirectory
    # Internal types
    VkException = 128
    VkGeneProcessor
    VkApplication
    VkPackage
    VkModule
    VkNamespace
    VkFunction
    VkBoundFunction
    VkMacro
    VkBlock
    VkClass
    VkMixin
    VkMethod
    VkNativeFn
    VkNativeFn2
    VkNativeMethod
    VkNativeMethod2
    VkInstance
    VkCast
    VkEnum
    VkEnumMember
    VkExpr
    VkExplode
    VkFuture
    VkThreadResult
    VkNativeFile

  Value* {.acyclic.} = ref object
    case kind*: ValueKind
    of VkAny:
      any*: pointer
      any_class*: Class
    of VkCustom:
      custom*: CustomValue
      custom_class*: Class
    of VkBool:
      bool*: bool
    of VkInt:
      int*: BiggestInt
    of VkRatio:
      ratio_num*: BiggestInt
      ratio_denom*: BiggestInt
    of VkFloat:
      float*: float
    of VkBin:
      bin*: seq[uint8]
      bin_bit_size*: uint
    of VkBin64:
      bin64*: uint64
      bin64_bit_size*: uint
    of VkByte:
      byte*: uint8
      byte_bit_size*: uint
    of VkBytes:
      bytes*: seq[uint8]
      # bytes_size*: uint # size is the len of bytes
    of VkChar:
      char*: char
      rune*: Rune
    of VkString, VkSymbol:
      str*: string
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
      map*: Table[string, Value]
    of VkVector:
      vec*: seq[Value]
    of VkSet:
      set*: HashSet[Value]
    of VkGene:
      gene_type*: Value
      gene_props*: Table[string, Value]
      gene_children*: seq[Value]
    of VkEnum:
      `enum`*: Enum
    of VkEnumMember:
      `enum_member`*: EnumMember
    of VkStream:
      stream*: seq[Value]
      stream_index*: BiggestInt
      stream_ended*: bool
    of VkDocument:
      document_type*: Value
      document_props*: Table[string, Value]
      document_children*: seq[Value]
    of VkFile:
      file_parent*: Value
      file_name*: string
      file_content*: Value
      file_permissions*: string
    of VkArchiveFile:
      arc_file_parent*: Value
      arc_file_name*: string
      arc_file_members*: Table[string, Value]
      arc_file_permissions*: string
    of VkDirectory:
      dir_parent*: Value
      dir_name*: string
      dir_members*: Table[string, Value]
      dir_permissions*: string
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
      exception*: ref system.Exception
    of VkGeneProcessor:
      gene_processor*: GeneProcessor
    of VkApplication:
      app*: Application
    of VkPackage:
      pkg*: Package
    of VkModule:
      module*: Module
    of VkNamespace:
      ns*: Namespace
    of VkFunction:
      fn*: Function
    of VkBoundFunction:
      bound_fn*: BoundFunction
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
    of VkNativeFn2:
      native_fn2*: NativeFn2
    of VkNativeMethod:
      native_method*: NativeMethod
    of VkNativeMethod2:
      native_method2*: NativeMethod2
    of VkInstance:
      instance_class*: Class
      instance_props*: Table[string, Value]
    of VkExpr:
      expr*: Expr
    of VkFuture:
      future*: Future[Value]
      ft_success_callbacks*: seq[Value]
      ft_failure_callbacks*: seq[Value]
    of VkThreadResult:
      # thread*: ? # The thread itself
      thread_result*: FlowVar[Value]
    of VkNativeFile:
      native_file*: File
    else:
      discard

  CustomValue* = ref object of RootObj

  Document* = ref object
    `type`: Value
    props*: Table[string, Value]
    children*: seq[Value]

  # applicable to numbers, characters
  Range* = ref object
    start*: Value
    `end`*: Value
    step*: Value # default to 1 if first is greater than last
    # include_start*: bool # always true
    include_end*: bool # default to false

  DateTimeInternal = ref object
    data: DateTime

  # Non-date specific time object
  Time* = ref object
    hour*: int
    minute*: int
    second*: int
    nanosec*: int
    timezone*: Timezone

  Exception* = object of CatchableError
    instance*: Value  # instance of Gene exception class

  NotDefinedException* = object of Exception
  # Types related to command line argument parsing
  ArgumentError* = object of Exception

  # index of a name in a scope
  NameIndexScope* = distinct int

  Translator* = proc(value: Value): Expr {.gcsafe.}
  Evaluator* = proc(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value {.gcsafe.}

  EvalCatch* = proc(self: VirtualMachine, frame: Frame, expr: var Expr): Value {.gcsafe.}
  EvalWrap* = proc(eval: Evaluator): Evaluator {.gcsafe.}

  TranslateCatch* = proc(value: Value): Expr {.gcsafe.}
  TranslateWrap* = proc(translate: Translator): Translator {.gcsafe.}

  NativeFn* = proc(args: Value): Value {.gcsafe, nimcall.}
  NativeFn2* = proc(args: Value): Value {.gcsafe.}
  NativeFnWrap* = proc(f: NativeFn): NativeFn2 {.gcsafe.}
  NativeMethod* = proc(self: Value, args: Value): Value {.gcsafe, nimcall.}
  NativeMethod2* = proc(self: Value, args: Value): Value {.gcsafe.}
  NativeMethodWrap* = proc(m: NativeMethod): NativeMethod2 {.gcsafe.}

  # NativeMacro is similar to NativeMethod, but args are not evaluated before passed in
  # To distinguish NativeMacro and NativeMethod, we just create Value with different kind
  # (i.e. VkNativeMacro vs VkNativeMethod)
  # NativeMacro* = proc(self: Value, args: Value): Value

  GeneProcessor* = ref object of RootObj
    name*: string
    translator*: Translator

  VirtualMachine* = ref object
    app*: Application
    runtime*: Runtime
    modules*: Table[string, Namespace]
    async_wait*: uint
    repl_on_error*: bool

    translators*: Table[ValueKind, Translator]
    gene_translators*: Table[string, Translator]

    global_ns*     : Value
    gene_ns*       : Value
    gene_native_ns*: Value
    genex_ns*      : Value

    object_class*   : Value
    nil_class*      : Value
    bool_class*     : Value
    int_class*      : Value
    float_class*    : Value
    char_class*     : Value
    string_class*   : Value
    symbol_class*   : Value
    complex_symbol_class*: Value
    array_class*    : Value
    map_class*      : Value
    set_class*      : Value
    gene_class*     : Value
    stream_class*   : Value
    document_class* : Value
    regex_class*    : Value
    range_class*    : Value
    date_class*     : Value
    datetime_class* : Value
    time_class*     : Value
    timezone_class* : Value
    selector_class* : Value
    exception_class*: Value
    class_class*    : Value
    mixin_class*    : Value
    application_class*: Value
    package_class*  : Value
    module_class*   : Value
    namespace_class*: Value
    function_class* : Value
    macro_class*    : Value
    block_class*    : Value
    future_class*   : Value
    thread_result_class*: Value
    file_class*     : Value

  # VirtualMachine depends on a Runtime
  Runtime* = ref object
    name*: string     # default/...
    pkg*: Package
    props*: Table[string, Value]  # Additional properties

  # It might not be very useful to group functionalities by features
  # because we can not easily disable features.
  # Instead we should define capabilities, e.g. file system access,
  # network access, environment access, input/output device access etc.
  # Capabilities can be enabled/disabled on application, package, module level.

  # environment: local/unittest/development/staging/production/...
  # assertion: enabled/disabled
  # log level: fatal/error/warning/info/debug/trace
  # repl on error: true/false
  # capabilities:
  #   environment variables: read/write
  #   stdin/stdout/stderr/pipe: read/write
  #   gui:
  #   file system: read/write
  #   os execution:
  #   database: read/write
  #   socket client: read/write
  #   socket server:
  #   http: get/post/put/...
  #   profile: read
  #   location: read
  #   notification: send
  #   custom capabilities provided by libraries
  #
  # Support on-demand capability request
  # Ideally on-demand request should be non-blocking and can be rejected.

  # Pseudo code for capabilities config (no hierarchy, evaluated in the order, rules defined later take precedence):
  # disable all
  # enable stdout [] write

  # enable filesystem [/home/user] [read, write]
  # disable filesystem [/home/user/.ssh]

  # Group capabilities
  # define X:
  #   enable filesystem [/home/user] [read, write]
  #   include Y
  #   ...

  ## This is the root of a running application
  Application* = ref object
    name*: string         # Default to base name of command, can be changed, e.g. ($set_app_name "...")
    pkg*: Package         # Entry package for the application
    ns*: Namespace
    cmd*: string
    args*: seq[string]
    main_module*: Module
    dep_root*: DependencyRoot
    props*: Table[string, Value]  # Additional properties

  Package* = ref object
    dir*: string          # Where the package assets are installed
    adhoc*: bool          # Adhoc package is created when package.gene is not found
    ns*: Namespace
    name*: string
    version*: Value
    license*: Value
    globals*: seq[string] # Global variables defined by this package
    dependencies*: Table[string, Dependency]
    homepage*: string
    src_path*: string     # Default to "src"
    test_path*: string    # Default to "tests"
    asset_path*: string   # Default to "assets"
    build_path*: string   # Default to "build"
    load_paths*: seq[string]
    init_modules*: seq[string]    # Modules that should be loaded when the package is used the first time
    props*: Table[string, Value]  # Additional properties
    doc*: Document        # content of package.gene

  Dependency* = ref object  # A dependency is like a virtual package
    package*: Package       # The package this is translated to
    name*: string
    version*: string
    `type`*: string         # e.g. git, github, path
    path*: string
    repo*: string
    commit*: string
    auto_load*: bool        # If true, the package is loaded and its init_modules are executed

  DependencyRoot* = ref object
    package*: Package
    map*: Table[string, seq[Package]] # Support loading different versions of same package
    children*: Table[string, DependencyNode]

  DependencyNode* = ref object
    package*: Package
    root*: DependencyRoot
    children*: Table[string, DependencyNode]

  SourceType* = enum
    StFile
    StVirtualFile # e.g. a file embeded in the source code or an archive file.
    StInline
    StRepl
    StEval

  Module* = ref object
    source_type*: SourceType
    source*: Value
    pkg*: Package         # Package in which the module is defined
    name*: string
    ns*: Namespace
    handle*: LibHandle    # Optional handle for dynamic lib
    props*: Table[string, Value]  # Additional properties

  Namespace* = ref object
    module*: Module
    parent*: Namespace
    stop_inheritance*: bool  # When set to true, stop looking up for members
    name*: string
    members*: Table[string, Value]
    on_member_missing*: seq[Value]

  Class* = ref object
    parent*: Class
    name*: string
    constructor*: Value
    methods*: Table[string, Method]
    on_extended*: Value
    # method_missing*: Value
    ns*: Namespace # Class can act like a namespace

  Mixin* = ref object
    name*: string
    methods*: Table[string, Method]
    on_included*: Value
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
    matcher*: RootMatcher
    matching_hint*: MatchingHint
    body*: seq[Value]
    body_compiled*: Expr
    ret*: Expr

  BoundFunction* = ref object of GeneProcessor
    target*: Value
    self*: Value
    # args*: Value

  Macro* = ref object of GeneProcessor
    ns*: Namespace
    parent_scope*: Scope
    parent_scope_max*: NameIndexScope
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

  Enum* = ref object
    name*: string
    members*: Table[string, EnumMember]

  EnumMember* = ref object
    parent*: Value
    name*: string
    value*: int

  Expr* = ref object of RootObj
    evaluator*: Evaluator

  FrameKind* = enum
    FrDefault
    FrModule
    FrFunction
    FrMacro
    FrMethod

  FrameExtra* = ref object
    case kind*: FrameKind
    of FrModule:
      `mod`*: Module
    of FrFunction:
      fn*: Function
    of FrMacro:
      `macro`*: Macro
    of FrMethod:
      `method`*: Method
    else:
      discard
    args*: Value # This is only available in some frames (e.g. function/macro/block)
    props*: Table[string, Value]

  Frame* = ref object
    parent*: Frame
    kind*: FrameKind  # this is in both Frame and FrameExtra and must be kept in sync.
    self*: Value
    ns*: Namespace
    scope*: Scope
    extra*: FrameExtra

  Scope* = ref object
    parent*: Scope
    parent_index_max*: NameIndexScope
    members*:  seq[Value]
    # Value of mappings is composed of two bytes:
    #   first is the optional index in self.mapping_history + 1
    #   second is the index in self.members
    mappings*: Table[string, int]
    mapping_history*: seq[seq[NameIndexScope]]

  Break* = ref object of CatchableError
    val*: Value

  Continue* = ref object of CatchableError

  Return* = ref object of CatchableError
    frame*: Frame
    val*: Value

  MatchingMode* = enum
    MatchArguments # (fn f [a b] ...)
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
    MatchType
    MatchProp
    MatchData
    MatchLiteral

  Matcher* = ref object
    root*: RootMatcher
    kind*: MatcherKind
    next*: Matcher  # if kind is MatchData and is_splat is true, we may need to check next matcher
    name*: string
    is_prop*: bool
    literal*: Value # if kind is MatchLiteral, this is required
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
    missing*: seq[string]
    # If wrong type
    expect_type*: string
    found_type*: string

  # Internal state when applying the matcher to an input
  # Limited to one level
  MatchState* = ref object
    # prop_processed*: seq[string]
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
    SmInvoke

  SelectorMatcher* = ref object
    root*: Selector
    case kind*: SelectorMatcherKind
    of SmByIndex:
      index*: int
    of SmByIndexRange:
      range*: Range
    of SmByName:
      name*: string
    of SmByType:
      by_type*: Value
    of SmCallback:
      callback*: Value
    of SmInvoke:
      invoke_name*: string
      invoke_args*: Value
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

  VmCallback* = proc(self: var VirtualMachine) {.gcsafe.}

var VM* {.threadvar.}: VirtualMachine  # The current virtual machine
var VmCreatedCallbacks*: seq[VmCallback] = @[]
var VmCreatedCallbacksAddr* = VmCreatedCallbacks.addr

#################### Definitions #################

proc new_gene_bool*(val: bool): Value {.gcsafe.}
proc new_gene_int*(val: BiggestInt): Value {.gcsafe.}
proc new_gene_float*(val: float): Value {.gcsafe.}
proc new_gene_char*(c: char): Value {.gcsafe.}
proc new_gene_char*(c: Rune): Value {.gcsafe.}
proc new_gene_string*(s: string): Value {.gcsafe.}
proc new_gene_string_move*(s: string): Value {.gcsafe.}
proc new_gene_vec*(items: seq[Value]): Value {.gcsafe.}
proc new_gene_vec*(items: varargs[Value]): Value {.gcsafe.}
proc new_gene_map*(): Value {.gcsafe.}
proc new_gene_map*(map: Table[string, Value]): Value {.gcsafe.}
proc new_namespace*(): Namespace {.gcsafe.}
proc new_namespace*(name: string): Namespace {.gcsafe.}
proc new_namespace*(parent: Namespace): Namespace {.gcsafe.}
proc `[]=`*(self: var Namespace, key: string, val: Value) {.inline.}
proc new_class*(name: string): Class {.gcsafe.}
proc new_class*(name: string, parent: Class): Class {.gcsafe.}
proc new_match_matcher*(): RootMatcher {.gcsafe.}
proc new_arg_matcher*(): RootMatcher {.gcsafe.}
proc hint*(self: RootMatcher): MatchingHint {.gcsafe.}

##################################################

proc todo*() =
  raise new_exception(Exception, "TODO")

proc todo*(message: string) =
  raise new_exception(Exception, "TODO: " & message)

proc not_allowed*(message: string) =
  raise new_exception(Exception, message)

proc not_allowed*() =
  not_allowed("Error: should not arrive here.")

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

proc is_symbol*(v: Value, s: string): bool =
  v.kind == VkSymbol and v.str == s

#################### Converters ##################

converter to_gene*(v: int): Value                     {.gcsafe.} = new_gene_int(v)
converter to_gene*(v: int64): Value                   {.gcsafe.} = new_gene_int(v)
converter to_gene*(v: bool): Value                    {.gcsafe.} = new_gene_bool(v)
converter to_gene*(v: float): Value                   {.gcsafe.} = new_gene_float(v)
converter to_gene*(v: string): Value                  {.gcsafe.} = new_gene_string(v)
converter to_gene*(v: char): Value                    {.gcsafe.} = new_gene_char(v)
converter to_gene*(v: Rune): Value                    {.gcsafe.} = new_gene_char(v)
converter to_gene*(v: Table[string, Value]): Value    {.gcsafe.} = new_gene_map(v)

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

converter biggest_to_int*(v: BiggestInt): int = cast[int](v)

converter seq_to_gene*(v: seq[Value]): Value {.gcsafe.} = new_gene_vec(v)
converter str_to_gene*(v: string): Value {.gcsafe.} = new_gene_string(v)

converter file_to_gene*(file: File): Value =
  Value(
    kind: VkNativeFile,
    native_file: file,
  )

converter int_to_scope_index*(v: int): NameIndexScope = cast[NameIndexScope](v)
converter scope_index_to_int*(v: NameIndexScope): int = cast[int](v)

converter gene_to_ns*(v: Value): Namespace = todo()

#################### VM ##########################

proc new_vm*(): VirtualMachine =
  return VirtualMachine(
    async_wait: ASYNC_WAIT_LIMIT,
  )

#################### Application #################

proc new_app*(): Application =
  result = Application()
  var global = new_namespace("global")
  result.ns = global

#################### Package #####################

proc normalize(self: Package, path: string): string =
  normalize_path(self.dir & "/" & path)

proc add_load_path*(self: Package, path: string) =
  var i = self.load_paths.find(path)
  if i >= 0:
    self.load_paths.delete(i)
  self.load_paths.insert(path, 0)

proc reset_load_paths*(self: Package, test_mode = false) =
  self.load_paths = @[normalize(self.dir)]
  if self.src_path == "":
    self.src_path = "src"
  self.add_load_path(self.normalize(self.src_path))
  if test_mode:
    if self.test_path == "":
      self.test_path = "tests"
    self.add_load_path(self.normalize(self.test_path))
  if self.build_path == "":
    self.build_path = "build"
  self.add_load_path(self.normalize(self.build_path))

#################### Module ######################

proc new_module*(pkg: Package, name: string): Module =
  result = Module(
    pkg: pkg,
    name: name,
    ns: new_namespace(VM.app.ns),
  )
  result.ns.module = result

proc new_module*(pkg: Package): Module =
  result = new_module(pkg, "<unknown>")

proc new_module*(pkg: Package, name: string, ns: Namespace): Module =
  result = Module(
    pkg: pkg,
    name: name,
    ns: new_namespace(ns),
  )
  result.ns.module = result

proc new_module*(pkg: Package, ns: Namespace): Module =
  result = new_module(pkg, "<unknown>", ns)

#################### Namespace ###################

proc new_namespace*(): Namespace =
  return Namespace(
    name: "<root>",
    members: Table[string, Value](),
  )

proc new_namespace*(parent: Namespace): Namespace =
  return Namespace(
    parent: parent,
    name: "<root>",
    members: Table[string, Value](),
  )

proc new_namespace*(name: string): Namespace =
  return Namespace(
    name: name,
    members: Table[string, Value](),
  )

proc new_namespace*(parent: Namespace, name: string): Namespace =
  return Namespace(
    parent: parent,
    name: name,
    members: Table[string, Value](),
  )

proc root*(self: Namespace): Namespace =
  if self.name == "<root>":
    return self
  else:
    return self.parent.root

proc get_module*(self: Namespace): Module =
  if self.module == nil:
    if self.parent != nil:
      return self.parent.get_module()
    else:
      return
  else:
    return self.module

proc package*(self: Namespace): Package =
  self.get_module().pkg

proc has_key*(self: Namespace, key: string): bool {.inline.} =
  return self.members.has_key(key) or (self.parent != nil and self.parent.has_key(key))

proc `[]`*(self: Namespace, key: string): Value {.inline.} =
  if self.members.has_key(key):
    return self.members[key]
  elif not self.stop_inheritance and self.parent != nil:
    return self.parent[key]
  else:
    raise new_exception(NotDefinedException, key & " is not defined")

proc locate*(self: Namespace, key: string): (Value, Namespace) {.inline.} =
  if self.members.has_key(key):
    result = (self.members[key], self)
  elif not self.stop_inheritance and self.parent != nil:
    result = self.parent.locate(key)
  else:
    not_allowed()

proc `[]=`*(self: var Namespace, key: string, val: Value) {.inline.} =
  self.members[key] = val

proc get_members*(self: Namespace): Value =
  result = new_gene_map()
  for k, v in self.members:
    result.map[k] = v

proc member_names*(self: Namespace): Value =
  result = new_gene_vec()
  for k, _ in self.members:
    result.vec.add(k)

#################### Scope #######################

proc new_scope*(): Scope = Scope(
  members: @[],
  mappings: Table[string, int](),
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

proc has_key(self: Scope, key: string, max: int): bool {.inline.} =
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

proc has_key*(self: Scope, key: string): bool {.inline.} =
  if self.mappings.has_key(key):
    return true
  elif self.parent != nil:
    return self.parent.has_key(key, self.parent_index_max)

proc def_member*(self: var Scope, key: string, val: Value) {.inline.} =
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

proc `[]`(self: Scope, key: string, max: int): Value {.inline.} =
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

proc `[]`*(self: Scope, key: string): Value {.inline.} =
  if self.mappings.has_key(key):
    var found = self.mappings[key]
    if found > 255:
      found = found and 0xFF
    return self.members[found]
  elif self.parent != nil:
    return self.parent[key, self.parent_index_max]

proc `[]=`(self: var Scope, key: string, val: Value, max: int) {.inline.} =
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

proc `[]=`*(self: var Scope, key: string, val: Value) {.inline.} =
  if self.mappings.has_key(key):
    self.members[self.mappings[key].int] = val
  elif self.parent != nil:
    self.parent.`[]=`(key, val, self.parent_index_max)
  else:
    not_allowed()

#################### Frame #######################

proc new_frame*(): Frame = Frame(
  self: Value(kind: VkNil),
)

proc new_frame*(kind: FrameKind): Frame = Frame(
  self: Value(kind: VkNil),
  kind: kind,
)

proc reset*(self: var Frame) {.inline.} =
  self.self = nil
  self.ns = nil
  self.scope = nil
  self.extra = nil

proc `[]`*(self: Frame, name: string): Value {.inline.} =
  result = self.scope[name]
  if result == nil:
    return self.ns[name]

proc `[]`*(self: Frame, name: Value): Value {.inline.} =
  case name.kind:
  of VkSymbol:
    result = self[name.str]
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
  #     result = self[csymbol[0]]
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

proc new_class*(name: string, parent: Class): Class =
  return Class(
    name: name,
    ns: new_namespace(nil, name),
    parent: parent,
  )

proc new_class*(name: string): Class =
  var parent: Class
  if VM.object_class != nil:
    parent = VM.object_class.class
  new_class(name, parent)

proc get_constructor*(self: Class): Value =
  self.constructor
  # if self.constructor.is_nil:
  #   if not self.parent.is_nil:
  #     return self.parent.get_constructor()
  # else:
  #   return self.constructor

proc has_method*(self: Class, name: string): bool =
  if self.methods.has_key(name):
    return true
  elif self.parent != nil:
    return self.parent.has_method(name)

proc get_method*(self: Class, name: string): Method =
  if self.methods.has_key(name):
    return self.methods[name]
  elif self.parent != nil:
    return self.parent.get_method(name)
  # else:
  #   not_allowed("No method available: " & name.to_s)

proc get_super_method*(self: Class, name: string): Method =
  if self.parent != nil:
    return self.parent.get_method(name)
  else:
    not_allowed("No super method available: " & name)

proc get_class*(val: Value): Class =
  case val.kind:
  of VkApplication:
    return VM.application_class.class
  of VkPackage:
    return VM.package_class.class
  of VkInstance:
    return val.instance_class
  of VkCast:
    return val.cast_class
  of VkClass:
    return VM.class_class.class
  of VkMixin:
    return VM.mixin_class.class
  of VkNamespace:
    return VM.namespace_class.class
  of VkFuture:
    return VM.future_class.class
  of VkThreadResult:
    return VM.thread_result_class.class
  of VkNativeFile:
    return VM.file_class.class
  of VkException:
    var ex = val.exception
    if ex is Exception:
      var ex = cast[Exception](ex)
      if ex.instance != nil:
        return ex.instance.instance_class
      else:
        return VM.exception_class.class
    else:
      return VM.exception_class.class
  of VkNil:
    return VM.nil_class.class
  of VkBool:
    return VM.bool_class.class
  of VkInt:
    return VM.int_class.class
  of VkChar:
    return VM.char_class.class
  of VkString:
    return VM.string_class.class
  of VkSymbol:
    return VM.symbol_class.class
  of VkComplexSymbol:
    return VM.complex_symbol_class.class
  of VkVector:
    return VM.array_class.class
  of VkMap:
    return VM.map_class.class
  of VkSet:
    return VM.set_class.class
  of VkGene:
    return VM.gene_class.class
  of VkRegex:
    return VM.regex_class.class
  of VkRange:
    return VM.range_class.class
  of VkDate:
    return VM.date_class.class
  of VkDateTime:
    return VM.datetime_class.class
  of VkTime:
    return VM.time_class.class
  of VkFunction:
    return VM.function_class.class
  of VkTimezone:
    return VM.timezone_class.class
  of VkAny:
    if val.any_class == nil:
      return VM.object_class.class
    else:
      return val.any_class
  of VkCustom:
    if val.custom_class == nil:
      return VM.object_class.class
    else:
      return val.custom_class
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

proc def_native_method*(self: Value, name: string, m: NativeMethod) =
  self.class.methods[name] = Method(
    class: self.class,
    name: name,
    callable: Value(kind: VkNativeMethod, native_method: m),
  )

proc def_native_method*(self: Value, name: string, m: NativeMethod2) =
  self.class.methods[name] = Method(
    class: self.class,
    name: name,
    callable: Value(kind: VkNativeMethod2, native_method2: m),
  )

proc def_native_constructor*(self: Value, f: NativeFn) =
  self.class.constructor = Value(kind: VkNativeFn, native_fn: f)

proc def_native_constructor*(self: Value, f: NativeFn2) =
  self.class.constructor = Value(kind: VkNativeFn2, native_fn2: f)

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

proc add_member*(self: var Value, name: string, value: int) =
  self.enum.members[name] = EnumMember(
    parent: self,
    name: name,
    value: value
  )

proc `==`*(this, that: EnumMember): bool =
  return this.parent == that.parent and this.name == that.name

#################### Date & Time #################

proc date*(self: Value): DateTime =
  self.date_internal.data

proc `==`*(this, that: Time): bool =
  return this.hour == that.hour and
    this.minute == that.minute and
    this.second == that.second and
    this.timezone == that.timezone

#################### Value #######################

proc new_gene_any*(v: pointer): Value =
  return Value(kind: VkAny, any: v)

proc new_gene_any*(v: pointer, class: Class): Value =
  return Value(kind: VkAny, any: v, any_class: class)

proc new_gene_custom*(c: CustomValue, class: Class): Value =
  Value(
    kind: VkCustom,
    custom_class: class,
    custom: c,
  )

proc new_gene_bool*(val: bool): Value =
  Value(kind: VkBool, bool: val)
  # case val
  # of true: return True
  # of false: return False

proc new_gene_bool*(s: string): Value =
  let parsed: bool = parseBool(s)
  return new_gene_bool(parsed)

proc new_gene_int*(): Value =
  return Value(kind: VkInt, int: 0)

proc new_gene_int*(s: string): Value =
  return Value(kind: VkInt, int: parseBiggestInt(s))

proc new_gene_int*(val: BiggestInt): Value {.gcsafe.} =
  return Value(kind: VkInt, int: val)

proc new_gene_ratio*(num, denom: BiggestInt): Value =
  return Value(kind: VkRatio, ratio_num: num, ratio_denom: denom)

proc new_gene_float*(s: string): Value =
  return Value(kind: VkFloat, float: parseFloat(s))

proc new_gene_float*(val: float): Value =
  return Value(kind: VkFloat, float: val)

proc new_gene_char*(c: char): Value =
  return Value(kind: VkChar, char: c)

proc new_gene_char*(c: Rune): Value =
  return Value(kind: VkChar, rune: c)

proc new_gene_string*(s: string): Value {.gcsafe.} =
  return Value(kind: VkString, str: s)

proc new_gene_string_move*(s: string): Value =
  result = Value(kind: VkString)
  shallowCopy(result.str, s)

proc new_gene_symbol*(name: string): Value =
  return Value(kind: VkSymbol, str: name)

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
    map: Table[string, Value](),
  )

proc new_gene_map*(map: Table[string, Value]): Value =
  return Value(
    kind: VkMap,
    map: map,
  )

proc new_gene_set*(items: varargs[Value]): Value =
  result = Value(
    kind: VkSet,
    set: HashSet[Value](),
  )
  for item in items:
    result.set.incl(item)

proc new_gene_gene*(): Value =
  return Value(
    kind: VkGene,
    gene_type: Value(kind: VkNil),
  )

proc new_gene_gene*(`type`: Value, children: varargs[Value]): Value =
  return Value(
    kind: VkGene,
    gene_type: `type`,
    gene_children: @children,
  )

proc new_gene_gene*(`type`: Value, props: Table[string, Value], children: varargs[Value]): Value =
  return Value(
    kind: VkGene,
    gene_type: `type`,
    gene_props: props,
    gene_children: @children,
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

# Do not allow auto conversion between CatchableError and Value
# because there are sub-classes of CatchableError that need to be
# handled differently.
proc exception_to_value*(ex: ref system.Exception): Value =
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

proc new_gene_processor*(name: string, translator: Translator): Value =
  return Value(
    kind: VkGeneProcessor,
    gene_processor: GeneProcessor(name: name, translator: translator),
  )

proc new_gene_processor*(translator: Translator): Value =
  return Value(
    kind: VkGeneProcessor,
    gene_processor: GeneProcessor(translator: translator),
  )

proc new_gene_class*(name: string): Value =
  return Value(
    kind: VkClass,
    class: new_class(name),
  )

proc new_gene_instance*(class: Class, props: Table[string, Value]): Value =
  return Value(
    kind: VkInstance,
    instance_class: class,
    instance_props: props,
  )

proc new_gene_future*(f: Future[Value]): Value =
  return Value(
    kind: VkFuture,
    future: f,
  )

proc is_truthy*(self: Value): bool =
  case self.kind:
  of VkBool:
    return self.bool
  of VkNil, VkVoid:
    return false
  else:
    return true

# proc is_empty*(self: Value): bool =
#   case self.kind:
#   of VkVoid, VkNil:
#     return true
#   of VkVector:
#     return self.vec.len == 0
#   of VkMap:
#     return self.map.len == 0
#   of VkSet:
#     return self.set.len == 0
#   of VkString:
#     return self.str.len == 0
#   else:
#     return false

proc merge*(self: var Value, value: Value) =
  case self.kind:
  of VkGene:
    case value.kind:
    of VkGene:
      for item in value.gene_children:
        self.gene_children.add(item)
      for k, v in value.gene_props:
        self.gene_props[k] = v
    of VkVector:
      for item in value.vec:
        self.gene_children.add(item)
    of VkMap:
      for k, v in value.map:
        self.gene_props[k] = v
    else:
      todo()
  of VkVector:
    case value.kind:
    of VkVector:
      for item in value.vec:
        self.gene_children.add(item)
    else:
      todo()
  else:
    todo()

# proc get_member*(self: Value, name: string): Value =
#   case self.kind:
#   of VkNamespace:
#     return self.ns[name.to_key]
#   of VkClass:
#     return self.class.ns[name.to_key]
#   of VkMixin:
#     return self.mixin.ns[name.to_key]
#   of VkEnum:
#     return self.enum[name]
#   else:
#     todo("get_member " & $self.kind & " " & name)

proc table_equals*(this, that: Table): bool =
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
    of VkString, VkSymbol:
      return this.str == that.str
    of VkComplexSymbol:
      return this.csymbol == that.csymbol
    of VkDate, VkDateTime:
      return this.date == that.date
    of VkTime:
      return this.time == that.time
    of VkTimezone:
      return this.timezone == that.timezone
    of VkSet:
      if this.set.len == that.set.len:
        for v in this.set.items:
          if not that.set.contains(v):
            return false
        return true
      else:
        return false
    of VkGene:
      return this.gene_type == that.gene_type and
        this.gene_children == that.gene_children and
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
    of VkClass:
      return this.class == that.class
    of VkEnum:
      return this.enum == that.enum
    of VkEnumMember:
      return this.enum_member == that.enum_member
    of VkCustom:
      return this.custom_class == that.custom_class and this.custom == that.custom
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
  of VkString, VkSymbol:
    h = h !& hash(node.str)
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
    h = h !& hash(node.gene_children)
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

proc `$`*(self: Class): string =
  if self.parent.is_nil or self.parent == VM.object_class.class:
    result = "(class $#)" % [self.name]
  else:
    result = "(class $# < $#)" % [self.name, self.parent.name]

proc `$`*(node: Value): string =
  if node.is_nil:
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
    result = node.str
  of VkComplexSymbol:
    result = node.csymbol.join("/")
  of VkRegex:
    result = "#/" & node.regex_pattern & "/"
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
      result &= k
      result &= " "
      result &= $v
    result &= "}"
  of VkGene:
    result = "(" & $node.gene_type
    if node.gene_props.len > 0:
      for k, v in node.gene_props:
        result &= " ^" & k & " " & $v
    if node.gene_children.len > 0:
      result &= " " & node.gene_children.join(" ")
    result &= ")"
  of VkFunction:
    result = "(fn $#)" % [node.fn.name]
  of VkMacro:
    result = "(macro $#)" % [node.macro.name]
  of VkNamespace:
    result = "(ns $#)" % [node.ns.name]
  of VkClass:
    result = $node.class
  of VkInstance:
    result = "($# " % [$node.instance_class]
    var is_first = true
    for k, v in node.instance_props:
      if is_first:
        is_first = false
      else:
        result &= " "
      result &= "^"
      result &= k
      result &= " "
      result &= $v
    result &= ")"
  of VkQuote:
    result = ":" & $node.quote
  of VkUnquote:
    result = "%" & $node.unquote
  else:
    result = $node.kind

proc wrap_with_try*(body: seq[Value]): seq[Value] =
  var found_catch_or_finally = false
  for item in body:
    if item.kind == VkSymbol and item.str in ["catch", "finally"]:
      found_catch_or_finally = true
  if found_catch_or_finally:
    return @[new_gene_gene(new_gene_symbol("try"), body)]
  else:
    return body

#################### Document ####################

proc new_doc*(children: seq[Value]): Document =
  return Document(children: children)

#################### File/Dir ####################

proc file_path*(self: Value): string =
  case self.kind:
  of VkFile:
    if self.file_parent.is_nil:
      return self.file_name
    else:
      return self.file_parent.file_path() & "/" & self.file_name
  of VkDirectory:
    if self.dir_parent.is_nil:
      return self.dir_name
    else:
      return self.dir_parent.file_path() & "/" & self.dir_name
  of VkArchiveFile:
    if self.arc_file_parent.is_nil:
      return self.arc_file_name
    else:
      return self.arc_file_parent.file_path() & "/" & self.arc_file_name
  else:
    not_allowed("file_path: " & $self)

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
    result.matchers.add(SelectorMatcher(kind: SmByName, name: v.str))
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
        result.matchers.add(SelectorMatcher(kind: SmByName, name: item.str))
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
proc is_singular*(self: Selector): bool {.gcsafe.}

proc is_singular*(self: SelectorItem): bool =
  case self.kind:
  of SiDefault:
    if self.matchers.len > 1:
      return false
    if self.matchers[0].kind notin [SmByIndex, SmByName, SmInvoke]:
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
    mode: MatchArguments,
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

# proc new_matched_field*(name: string, value: Value): MatchedField =
#   result = MatchedField(
#     name: name,
#     value: value,
#   )

proc props*(self: seq[Matcher]): HashSet[string] =
  for m in self:
    if m.kind == MatchProp and not m.is_splat:
      result.incl(m.name)

proc prop_splat*(self: seq[Matcher]): string =
  for m in self:
    if m.kind == MatchProp and m.is_splat:
      return m.name

##################################################

template eval*(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  if self.async_wait == 0:
    self.async_wait = ASYNC_WAIT_LIMIT
    try:
      poll()
    except ValueError as e:
      if e.msg == "No handles or timers registered in dispatcher.":
        discard
      else:
        raise
  else:
    self.async_wait -= 1
  expr.evaluator(self, frame, nil, expr)

proc eval_catch*(self: VirtualMachine, frame: Frame, expr: var Expr): Value =
  try:
    result = self.eval(frame, expr)
  except system.Exception as e:
    # echo e.msg & "\n" & e.getStackTrace()
    result = Value(
      kind: VkException,
      exception: e,
    )

proc eval_wrap*(e: Evaluator): Evaluator =
  return proc(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
    result = e(self, frame, target, expr)
    if result != nil and result.kind == VkException:
      raise result.exception

# proc(){.nimcall.} can not access local variables
# Workaround: create a new type like RemoteFn that does not use nimcall
proc fn_wrap*(f: NativeFn): NativeFn2 =
  return proc(args: Value): Value {.gcsafe.} =
    result = f(args)
    if result != nil and result.kind == VkException:
      raise result.exception

proc method_wrap*(m: NativeMethod): NativeMethod2 =
  return proc(self, args: Value): Value =
    result = m(self, args)
    if result != nil and result.kind == VkException:
      raise result.exception

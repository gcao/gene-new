import tables, hashes

type
  MapKey* = distinct int

  Mapping* = ref object
    keys*: seq[string]
    map*: Table[string, MapKey]

var mapping* = Mapping(
  keys: @[],
  map: Table[string, MapKey](),
)

converter to_key*(i: int): MapKey {.inline.} =
  result = cast[MapKey](i)

proc add_key*(s: string): MapKey {.inline.} =
  if mapping.map.has_key(s):
    result = mapping.map[s]
  else:
    result = mapping.keys.len
    mapping.keys.add(s)
    mapping.map[s] = result

proc to_key*(s: string): MapKey {.inline.} =
  if mapping.map.has_key(s):
    result = mapping.map[s]
  else:
    result = add_key(s)

proc to_s*(self: MapKey): string {.inline.} =
  result = mapping.keys[cast[int](self)]

proc `%`*(self: MapKey): string =
  result = mapping.keys[cast[int](self)]

converter to_strings*(self: seq[MapKey]): seq[string] {.inline.} =
  for k in self:
    result.add(k.to_s)

converter to_keys*(self: seq[string]): seq[MapKey] {.inline.} =
  for item in self:
    result.add(item.to_key)

proc `==`*(this, that: MapKey): bool {.inline.} =
  result = cast[int](this) == cast[int](that)

proc hash*(self: MapKey): Hash {.inline.} =
  result = cast[int](self)

# TODO: automate adding built-in keys as constants, e.g. use a script that takes a csv file of name and string

const EMPTY_STRING_KEY*       = 0; discard add_key("")
const GLOBAL_KEY*             = 1; discard add_key("global")

let SELF_KEY*                 = add_key("self")
let METHOD_KEY*               = add_key("method")
let NAME_KEY*                 = add_key("name")
let VERSION_KEY*              = add_key("version")
let LOCATION_KEY*             = add_key("location")
let DEPENDENCIES_KEY*                 = add_key("dependencies")
let COND_KEY*                 = add_key("cond")
let THEN_KEY*                 = add_key("then")
let ELIF_KEY*                 = add_key("elif")
let ELSE_KEY*                 = add_key("else")
let NAMES_KEY*                = add_key("names")
let MODULE_KEY*               = add_key("module")
let APP_KEY*                  = add_key("$app")
let CUR_EXCEPTION_KEY*        = add_key("$ex")
let PKG_KEY*                  = add_key("pkg")
let ARGS_KEY*                 = add_key("args")
let TYPE_KEY*                 = add_key("type")
let TOGGLE_KEY*               = add_key("toggle")
let MULTIPLE_KEY*             = add_key("multiple")
let REQUIRED_KEY*             = add_key("required")
let DEFAULT_KEY*              = add_key("default")
let DISCARD_KEY*              = add_key("discard")
let ENUM_KEY*                 = add_key("enum")
let RANGE_KEY*                = add_key("range")
let DO_KEY*                   = add_key("do")
let LOOP_KEY*                 = add_key("loop")
let WHILE_KEY*                = add_key("while")
let FOR_KEY*                  = add_key("for")
let BREAK_KEY*                = add_key("break")
let CONTINUE_KEY*             = add_key("continue")
let IF_KEY*                   = add_key("if")
let NOT_KEY*                  = add_key("not")
let CASE_KEY*                 = add_key("case")
let WHEN_KEY*                 = add_key("when")
let VAR_KEY*                  = add_key("var")
let THROW_KEY*                = add_key("throw")
let TRY_KEY*                  = add_key("try")
let FN_KEY*                   = add_key("fn")
let MACRO_KEY*                = add_key("macro")
let RETURN_KEY*               = add_key("return")
let ASPECT_KEY*               = add_key("aspect")
let BEFORE_KEY*               = add_key("before")
let AFTER_KEY*                = add_key("after")
let NS_KEY*                   = add_key("ns")
let IMPORT_KEY*               = add_key("import")
let FROM_KEY*                 = add_key("from")
let STOP_INHERITANCE_KEY*     = add_key("$stop_inheritance")
let CLASS_KEY*                = add_key("class")
let OBJECT_KEY*               = add_key("object")
let NATIVE_METHOD_KEY*        = add_key("native_method")
let NEW_KEY*                  = add_key("new")
let INIT_KEY*                 = add_key("init")
let SUPER_KEY*                = add_key("super")
let INVOKE_METHOD_KEY*        = add_key("$invoke_method")
let MIXIN_KEY*                = add_key("mixin")
let INCLUDE_KEY*              = add_key("include")
let DOLLAR_INCLUDE_KEY*       = add_key("$include")
let PARSE_KEY*                = add_key("$parse")
let EVAL_KEY*                 = add_key("eval")
let CALLER_EVAL_KEY*          = add_key("caller_eval")
let MATCH_KEY*                = add_key("match")
let QUOTE_KEY*                = add_key("quote")
let UNQUOTE_KEY*              = add_key("unquote")
let ENV_KEY*                  = add_key("env")
let EXIT_KEY*                 = add_key("exit")
let PRINT_KEY*                = add_key("print")
let PRINTLN_KEY*              = add_key("println")
let EQ_KEY*                   = add_key("=")
let CALL_KEY*                 = add_key("call")
let GET_KEY*                  = add_key("$get")
let SET_KEY*                  = add_key("$set")
let DEF_MEMBER_KEY*           = add_key("$def_member")
let DEF_NS_MEMBER_KEY*        = add_key("$def_ns_member")
let GET_CLASS_KEY*            = add_key("$get_class")
let BLOCK_KEY*                = add_key("->")
let PARSE_CMD_ARGS_KEY*       = add_key("$parse_cmd_args")
let REPL_KEY*                 = add_key("repl")
let ASYNC_KEY*                = add_key("async")
let AWAIT_KEY*                = add_key("await")
let ON_FUTURE_SUCCESS_KEY*    = add_key("$on_future_success")
let ON_FUTURE_FAILURE_KEY*    = add_key("$on_future_failure")
let SELECTOR_KEY*             = add_key("@")
let SELECTOR_PARALLEL_KEY*    = add_key("@*")
let CMD_ARGS_KEY*             = add_key("$cmd_args")
let CLASS_OPTION_KEY*         = add_key("$class")
let METHOD_OPTION_KEY*        = add_key("$method")
let TODO_KEY*                 = add_key("todo")
let NOT_ALLOWED_KEY*          = add_key("not_allowed")
let GENE_KEY*                 = add_key("gene")
let GENEX_KEY*                = add_key("genex")
let NATIVE_KEY*               = add_key("native")
let FILE_KEY*                 = add_key("$file")
let ADD_KEY*                  = add_key("+")
let SUB_KEY*                  = add_key("-")
let MUL_KEY*                  = add_key("*")
let DIV_KEY*                  = add_key("/")
let STDIN_KEY*                = add_key("stdin")
let STDOUT_KEY*               = add_key("stdout")
let STDERR_KEY*               = add_key("stderr")
let OBJECT_CLASS_KEY*         = add_key("Object")
let EXCEPTION_CLASS_KEY*      = add_key("Exception")
let APPLICATION_CLASS_KEY*    = add_key("Application")
let PACKAGE_CLASS_KEY*        = add_key("Package")
let CLASS_CLASS_KEY*          = add_key("Class")
let NAMESPACE_CLASS_KEY*      = add_key("Namespace")
let FUNCTION_CLASS_KEY*       = add_key("Function")
let FUTURE_CLASS_KEY*         = add_key("Future")
let FILE_CLASS_KEY*           = add_key("File")
let NIL_CLASS_KEY*            = add_key("Nil")
let BOOL_CLASS_KEY*           = add_key("Bool")
let INT_CLASS_KEY*            = add_key("Int")
let CHAR_CLASS_KEY*           = add_key("Char")
let STRING_CLASS_KEY*         = add_key("String")
let SYMBOL_CLASS_KEY*         = add_key("Symbol")
let COMPLEX_SYMBOL_CLASS_KEY* = add_key("ComplexSymbol")
let ARRAY_CLASS_KEY*          = add_key("Array")
let MAP_CLASS_KEY*            = add_key("Map")
let SET_CLASS_KEY*            = add_key("Set")
let GENE_CLASS_KEY*           = add_key("Gene")
let REGEX_CLASS_KEY*          = add_key("Regex")
let RANGE_CLASS_KEY*          = add_key("Range")
let DATE_CLASS_KEY*           = add_key("Date")
let DATETIME_CLASS_KEY*       = add_key("DateTime")
let TIME_CLASS_KEY*           = add_key("Time")
let TIMEZONE_CLASS_KEY*       = add_key("Timezone")
let REQUEST_CLASS_KEY*        = add_key("Request")

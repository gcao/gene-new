# Credit:
# The parser and basic data types are built on top of EDN Parser[1] that is
# created by Roland Sadowski.
# 1. https://github.com/rosado/edn.nim

import lexbase, streams, strutils, unicode, tables, sets, times, nre, base64, os

import ./types

type
  ParseError* = object of CatchableError
  ParseEofError* = object of ParseError

  ParseMode* = enum
    PmDefault
    PmDocument
    PmStream
    PmFirst
    # PmPackage
    PmArchive

  ParseOptions* {.acyclic.} = ref object
    parent*: ParseOptions
    data*: Table[string, Value]
    units*: Table[string, Value]

  Parser* = object of BaseLexer
    mode*: ParseMode
    options*: ParseOptions
    filename*: string
    str*: string
    in_str_interpolation*: bool   # true if we are inside a string interpolation
    num_with_units*: seq[(TokenKind, string, string)] # token kind + number + unit
    # document*: Document
    token_kind*: TokenKind
    error*: ParseErrorKind
    references*: References
    done*: bool
    paused*: bool
    # document_props_done*: bool  # flag to tell whether we have read document properties
    handler*: ParseHandler

  TokenKind* = enum
    TkError
    TkEof
    TkString
    TkInt
    TkFloat
    TkNumberWithUnit
    TkDate
    TkDateTime
    TkTime

  ParseErrorKind* = enum
    ErrNone
    ErrInvalidToken
    ErrEofExpected
    ErrQuoteExpected
    ErrRegexEndExpected

  ParseInfo* = tuple[line, col: int]

  # ParseScope* = ref object
  #   parent*: ParseScope
  #   mappings*: Table[string, Value]

  # ParseFunction* = proc(self: var Parser, scope: ParseScope, props: Table[string, Value], children: seq[Value]): Value

  # ParseHandlerType* = enum
  #   PhDefault
  #   PhNativeFn

  # ParseHandler* = ref object of CustomValue
  #   is_macro*: bool  # if true, do not evaluate arguments before calling function
  #   case `type`*: ParseHandlerType
  #   of PhNativeFn:
  #     native_fn: ParseFunction
  #   else:
  #     scope*: ParseScope
  #     args*: seq[Value]
  #     body*: seq[Value]

  MacroReader = proc(p: var Parser): Value {.gcsafe.}
  MacroArray = array[char, MacroReader]

  MapKind = enum
    MkMap
    MkGene
    MkDocument

  PropState = enum
    PropKey
    PropValue

  DelimitedListResult = object
    list: seq[Value]
    map: Table[string, Value]

  Handler = proc(self: var Parser, input: Value): Value {.gcsafe.}

  StreamHandler = proc(value: Value)

  ParseEventKind* = enum
    PeStart
    PeEnd             # EOF
    PeStartDocument
    PeEndDocument
    PeStartVector     # [
    PeStartSet        # #[
    PeEndVectorOrSet  # ]
    PeStartMap
    PeEndMap
    PeMapShortcut
    PeStartGene
    PeEndGene
    PeStartStream
    PeEndStream
    PeKey
    PeValue
    PeToken           # processed by the PreprocessingHandler before being passed down to the next handler
    PeStartStrInterpolation   # #"
    PeStartStrMap             # #{
    PeStartStrVector          # #[
    PeStartStrGene            # #(
    PeStartStrComment         # #<
    PeEndStrInterpolation     # "
    PeStartStrInterpolation3  # #"""
    PeEndStrInterpolation3    # """
    PeQuote
    PeUnquote
    PeStartDecorator  # processed by the PreprocessingHandler
    PeComment         # Will not be emitted unless the parser is configured to do so.
    PeDocumentComment # Will not be emitted unless the parser is configured to do so.
    PeError
    # PeNewLine         # Can be useful to support different syntaxes.
    # PeIndent          # Can be useful to support different syntaxes.
    # PeSemicolon       # Can be useful to support different syntaxes.
    # PeComma           # Can be useful to support different syntaxes.
    # PeCustom          # Custom events defined by custom handlers

  ParseEvent* = ref object
    case kind*: ParseEventKind
    of PeValue:
      value*: Value
    of PeKey, PeMapShortcut:
      key*: string
    of PeToken:
      token*: string
    of PeComment, PeDocumentComment:
      comment*: string
    of PeError:
      error_code*: string
      error_message*: string
    else:
      discard
    # event_start: uint32
    # event_end: uint32

  # Multiple handlers can be used for the same parsing process.
  # Each handler should keep track of its own state, e.g. whether it's expecting the gene type
  # or not.
  ParseHandler* = ref object of RootObj
    parser*: ptr Parser
    next*: ParseHandler
    # The handler can consume the event and generate zero or more events to be processed
    # by next handler.
    handle*: proc(self: ParseHandler, event: ParseEvent) {.locks: "unknown".}

  PrepHandlerState* = enum
    PhDefault

    PhDocStart
    PhDocPropKey
    PhDocPropValue
    PhDocChild
    PhDocPropChild  # For readability's sake, we require the properties to appear before children.
    PhDocEnd

    # For Gene parsing:
    # (): Start -> End
    # (a): Start -> Type -> End
    # (a ^b c ^d e f): Start -> Type -> TypePropKey -> TypePropValue -> TypePropChild -> TypePropChild -> End
    # (a b c): Start -> Type -> TypeChild -> TypeChild -> End
    # (a b c ^d e ^f g h): Start -> Type -> TypeChild -> TypeChild -> TypeChildPropKey -> TypeChildPropValue -> TypeChildPropKey -> TypeChildPropValue -> TypePropChild -> End
    PhGeneStart
    PhGeneEnd
    PhGeneType
    PhGeneTypePropKey
    PhGeneTypePropValue
    PhGeneTypeChild
    PhGeneTypeChildPropKey
    PhGeneTypeChildPropValue
    PhGeneTypePropChild

    PhMapStart
    PhMapKey
    PhMapValue
    PhMapEnd

    PhMapShortcut

    PhVectorStart
    PhVectorEnd
    PhVectorValue

    PhSetStart
    PhSetEnd
    PhSetValue

    PhStrInterpolation
    # PhStrInterpolationStart
    # PhStrInterpolationString      # #"..."
    # PhStrInterpolationMapOrValue  # #{a} or #{^a b}
    # PhStrInterpolationVector      # #[...]
    # PhStrInterpolationGene        # #(...)
    # PhStrInterpolationComment     # #<...>#

    PhQuote
    PhUnquote

    PhDecoratorStart
    PhDecoratorFirst

  PrepHandlerContext* = ref object
    state*: PrepHandlerState
    key*: string
    value*: Value
    `defer`*: bool  # Whether to defer the event to the next handler.

  # We would like to share as little as possible between the PreprocessingHandler and the ValueHandler.
  # However, we would like to achieve the best performance possible. So we need to minimize the number
  # of allocations and copies etc.

  # Handle basic parsing and pre-processing (e.g. ???), raise errors if the input is not valid Gene data.
  PreprocessingHandler* = ref object of ParseHandler
    stack*: seq[PrepHandlerContext]

  ValueHandlerState* = enum
    VhDefault

    VhDocStart
    VhDocPropKey
    VhDocPropValue
    VhDocChild
    VhDocPropChild  # For readability's sake, we require the properties to appear before children.
    VhDocEnd

    # For Gene parsing:
    # (): Start -> End
    # (a): Start -> Type -> End
    # (a ^b c ^d e f): Start -> Type -> TypePropKey -> TypePropValue -> TypePropChild -> TypePropChild -> End
    # (a b c): Start -> Type -> TypeChild -> TypeChild -> End
    # (a b c ^d e ^f g h): Start -> Type -> TypeChild -> TypeChild -> TypeChildPropKey -> TypeChildPropValue -> TypeChildPropKey -> TypeChildPropValue -> TypePropChild -> End
    VhGeneStart
    VhGeneEnd
    VhGeneType
    VhGeneTypePropKey
    VhGeneTypePropValue
    VhGeneTypeChild
    VhGeneTypeChildPropKey
    VhGeneTypeChildPropValue
    VhGeneTypePropChild

    VhMapStart
    VhMapKey
    VhMapValue
    VhMapEnd

    VhMapShortcut

    VhVectorStart
    VhVectorEnd
    VhVectorValue

    VhSetStart
    VhSetEnd
    VhSetValue

    VhQuote
    VhUnquote

    VhDecoratorStart
    VhDecoratorFirst

  ValueHandlerContext* = ref object
    state*: ValueHandlerState
    key*: string
    value*: Value

  # For retrieving the first value from the parser
  ValueHandler* = ref object of ParseHandler
    stack*: seq[ValueHandlerContext]

const non_constituents: seq[char] = @[]

var INITIALIZED {.threadvar.}: bool
var DEFAULT_UNITS {.threadvar.}: Table[string, Value]
var HEX {.threadvar.}: Table[char, uint8]
var DATE_FORMAT {.threadvar.}: TimeFormat
var DATETIME_FORMAT {.threadvar.}: TimeFormat
var Ignore {.threadvar.}: Value

var macros {.threadvar.}: MacroArray
var dispatch_macros {.threadvar.}: MacroArray

var handlers {.threadvar.}: Table[string, Handler]

#################### Interfaces ##################

proc init*() {.gcsafe.}
proc keys*(self: ParseOptions): HashSet[string]
proc `[]`*(self: ParseOptions, name: string): Value
proc unit_keys*(self: ParseOptions): HashSet[string]
proc `unit`*(self: ParseOptions, name: string): Value
proc read*(self: var Parser): Value {.gcsafe.}
proc skip_comment(self: var Parser)
proc skip_block_comment(self: var Parser) {.gcsafe.}
proc skip_ws(self: var Parser) {.gcsafe.}
proc interpret_token(token: string): Value
proc read_map(self: var Parser, mode: MapKind): Table[string, Value] {.gcsafe.}

#################### Implementations #############

converter to_int(c: char): int = result = ord(c)

#################### ParseOptions ################

proc default_options*(): ParseOptions =
  result = ParseOptions()
  for k, v in DEFAULT_UNITS:
    result.units[k] = v

proc new_options*(prototype: ParseOptions): ParseOptions =
  result = ParseOptions()
  for k in prototype.keys().items:
    result.data[k] = prototype[k]
  for k in prototype.unit_keys.items:
    result.units[k] = prototype.unit(k)

proc extend*(self: ParseOptions): ParseOptions =
  ParseOptions(
    parent: self,
    data: init_table[string, Value](),
    units: init_table[string, Value](),
  )

proc keys*(self: ParseOptions): HashSet[string] =
  result = init_hash_set[string]()
  for k in self.data.keys:
    result.incl(k)
  for k in self.parent.keys():
    result.incl(k)

proc `[]`*(self: ParseOptions, name: string): Value =
  if self.data.has_key(name):
    return self.data[name]
  elif not self.parent.is_nil:
    return self.parent[name]
  else:
    return nil

proc `[]=`*(self: ParseOptions, name: string, value: Value) =
  self.data[name] = value

proc unit_keys*(self: ParseOptions): HashSet[string] =
  result = init_hash_set[string]()
  for k in self.units.keys:
    result.incl(k)
  for k in self.parent.unit_keys():
    result.incl(k)

proc `unit`*(self: ParseOptions, name: string): Value =
  if self.units.has_key(name):
    return self.units[name]
  elif not self.parent.is_nil:
    return self.parent.unit(name)
  else:
    return nil

#################### Event Handling ##############

proc `$`*(self: ParseEvent): string =
  case self.kind:
  of PeValue:
    result = $self.kind & " value=" & $self.value
  of PeToken:
    result = $self.kind & " token=" & $self.token
  of PeKey:
    result = $self.kind & " key=" & $self.key
  else:
    result = $self.kind

type
  KeyParsed* = object
    keys*: seq[string]
    value*: Value

# TODO: handle all cases
# @arg key: the key to be parsed, e.g. "^a", "^^a", "^!a", "^a^b", "^a^^b", "^a^!b", "^a^b^^c" etc
proc parse_key(key: string): KeyParsed =
  var i = 0
  var s = ""
  while i < key.len:
    let ch = key[i]
    case ch:
    of '^':
      if s.len > 0:
        result.keys.add(s)
        s = ""
      if key[i+1] == '^':
        result.value = true
        inc i
      elif key[i+1] == '!':
        result.value = Value(kind: VkNil)
        inc i
    else:
      s.add(ch)
    inc i
  result.keys.add(s)

proc merge_maps(first, second: Value) =
  if first.kind != VkMap or second.kind != VkMap:
    raise newException(ValueError, "merge_map: both values must be maps")
  for k, v in second.map:
    if first.map.has_key(k):
      raise newException(ValueError, "merge_map: key already exists: " & $k)
    first.map[k] = v

template do_handle(self: ParseHandler, event: ParseEvent) =
  self.handle(self, event)

proc handle_preprocess(h: ParseHandler, event: ParseEvent) =
  var self = cast[PreprocessingHandler](h)
  # echo "PreprocessingHandler " & $event
  case event.kind:
  of PeStart:
    self.next.do_handle(event)
    if self.parser.mode == PmDocument:
      var context = PrepHandlerContext(state: PhDocStart)
      self.stack.add(context)
      self.next.do_handle(event)
      self.next.do_handle(ParseEvent(kind: PeStartDocument))
  of PeEnd:
    self.next.do_handle(event)
  of PeValue:
    if self.stack.len > 0:
      var last = self.stack[^1]
      case last.state:
      of PhMapKey:
        last.state = PhMapValue
        self.next.do_handle(event)
      of PhStrInterpolation:
        last.value.gene_children.add(event.value)
        self.parser.in_str_interpolation = true
      else:
        self.next.do_handle(event)
    else:
      self.next.do_handle(event)
  of PeToken:
    if event.token[0] == '^':
      let parsed = parse_key(event.token)
      self.next.do_handle(ParseEvent(kind: PeKey, key: parsed.keys[0]))
      if parsed.keys.len > 1:
        for key in parsed.keys[1..^1]:
          self.next.do_handle(ParseEvent(kind: PeMapShortcut, key: key))
      if not parsed.value.is_nil:
        self.next.do_handle(ParseEvent(kind: PeValue, value: parsed.value))
    else:
      let value = interpret_token(event.token)
      let event = ParseEvent(kind: PeValue, value: value)
      self.next.do_handle(event)
  of PeStartVector:
    var context = PrepHandlerContext(state: PhVectorStart)
    self.stack.add(context)
    self.next.do_handle(event)
  of PeEndVectorOrSet:
    let context = self.stack.pop()
    if context.defer:
      let last = self.stack[^1]
      case last.state:
      of PhStrInterpolation:
        last.value.gene_children.add(context.value)
        self.parser.in_str_interpolation = true
      else:
        self.next.do_handle(ParseEvent(kind: PeValue, value: context.value))
    else:
      self.next.do_handle(event)
  of PeStartMap:
    var context = PrepHandlerContext(state: PhMapStart)
    self.stack.add(context)
    self.next.do_handle(event)
  of PeEndMap:
    discard self.stack.pop()
    self.next.do_handle(event)
  of PeStartGene:
    var context = PrepHandlerContext(state: PhGeneStart)
    self.stack.add(context)
    self.next.do_handle(event)
  of PeEndGene:
    discard self.stack.pop()
    self.next.do_handle(event)
  of PeStartSet:
    var context = PrepHandlerContext(state: PhSetStart)
    self.stack.add(context)
    self.next.do_handle(event)
  of PeQuote, PeUnquote:
    self.next.do_handle(event)
  of PeStartDecorator:
    self.next.do_handle(event)
  of PeStartStrInterpolation:
    var context = PrepHandlerContext(
      state: PhStrInterpolation,
      value: new_gene_gene(new_gene_symbol("#Str")),
    )
    self.stack.add(context)
    self.parser.in_str_interpolation = true
  of PeStartStrVector:
    var context = PrepHandlerContext(
      state: PhVectorStart,
      value: new_gene_vec(),
      `defer`: true,
    )
    self.stack.add(context)
    self.parser.in_str_interpolation = false
  of PeEndStrInterpolation:
    let last = self.stack.pop()
    var all_are_string = true
    for child in last.value.gene_children:
      if child.kind != VkString:
        all_are_string = false
        break
    if all_are_string:
      let value = new_gene_string("")
      for child in last.value.gene_children:
        value.str.add(child.str)
      self.next.do_handle(ParseEvent(kind: PeValue, value: value))
    else:
      self.next.do_handle(ParseEvent(kind: PeValue, value: last.value))
  else:
    todo($event)

proc unwrap(self: ValueHandler) {.inline.} =
  case self.stack.len:
  of 0:
    raise newException(ValueError, "unwrap: no value")
  of 1:
    self.parser.paused = true
  else:
    let value = self.stack.pop().value
    var last = self.stack[^1]
    case last.state:
    of VhVectorStart:
      last.value.vec.add(value)
    of VhSetStart:
      last.value.set.incl(value)
    of VhMapKey:
      last.state = VhMapValue
      if last.value.map.has_key(last.key):
        var found = last.value.map[last.key]
        if found.kind == VkMap and value.kind == VkMap:
          merge_maps(found, value)
        else:
          not_allowed("Duplicate key: " & $last.key)
      else:
        last.value.map[last.key] = value
    of VhMapShortcut:
      while true:
        var value = last.value
        value.map[last.key] = value
        discard self.stack.pop()
        last = self.stack[^1]
        case last.state
        of VhMapKey:
          last.state = VhMapValue
          if last.value.map.has_key(last.key):
            merge_maps(last.value.map[last.key], value)
          else:
            last.value.map[last.key] = value
          break
        of VhGeneTypePropKey:
          last.state = VhGeneTypePropValue
          if last.value.gene_props.has_key(last.key):
            merge_maps(last.value.gene_props[last.key], value)
          else:
            last.value.gene_props[last.key] = value
          break
        of VhMapShortcut:
          discard
        else:
          todo($last.state)
    of VhGeneStart:
      last.state = VhGeneType
      last.value.gene_type = value
    of VhGeneType, VhGeneTypeChild:
      last.state = VhGeneTypeChild
      last.value.gene_children.add(value)
    of VhGeneTypePropKey:
      last.state = VhGeneTypePropValue
      last.value.gene_props[last.key] = value
    of VhGeneTypeChildPropKey:
      last.state = VhGeneTypeChildPropValue
      last.value.gene_props[last.key] = value
    of VhGeneTypePropValue, VhGeneTypePropChild, VhGeneTypeChildPropValue:
      last.state = VhGeneTypePropChild
      last.value.gene_children.add(value)
    of VhQuote:
      case self.stack.len:
      of 1:
        self.parser.paused = true
        last.state = VhDefault
        last.value = Value(kind: VkQuote, quote: value)
      else:
        discard self.stack.pop()
        last = self.stack[^1]
    of VhUnquote:
      case self.stack.len:
      of 1:
        self.parser.paused = true
        last.state = VhDefault
        last.value = Value(kind: VkUnquote, unquote: value)
      else:
        discard self.stack.pop()
        last = self.stack[^1]
    of VhDecoratorStart:
      last.state = VhDecoratorFirst
      last.value = new_gene_gene(value)
    of VhDecoratorFirst:
      last.value.gene_children.add(value)
      case self.stack.len:
      of 1:
        self.parser.paused = true
      else:
        discard self.stack.pop()
        last = self.stack[^1]
    else:
      todo($last.state)

proc post_value_callback(self: ValueHandler, event: ParseEvent) {.inline.} =
  if self.stack.len == 0:
    self.parser.paused = true
    var context = ValueHandlerContext(state: VhDefault, value: event.value)
    self.stack.add(context)
  else:
    var last = self.stack[^1]
    case last.state:
    of VhDocPropKey:
      last.value.document.props[last.key] = event.value
      last.state = VhDocPropValue
    of VhDocStart, VhDocPropValue:
      last.value.document.children.add(event.value)
      last.state = VhDocPropValue
    of VhVectorStart:
      last.value.vec.add(event.value)
    of VhSetStart:
      last.value.set.incl(event.value)
    of VhMapKey:
      last.state = VhMapValue
      if last.value.map.has_key(last.key):
        var found = last.value.map[last.key]
        if found.kind == VkMap and event.value.kind == VkMap:
          merge_maps(found, event.value)
        else:
          not_allowed("Duplicate key: " & $last.key)
      else:
        last.value.map[last.key] = event.value
    of VhMapShortcut:
      while true:
        var value = last.value
        value.map[last.key] = event.value
        discard self.stack.pop()
        last = self.stack[^1]
        case last.state
        of VhMapKey:
          last.state = VhMapValue
          if last.value.map.has_key(last.key):
            merge_maps(last.value.map[last.key], value)
          else:
            last.value.map[last.key] = value
          break
        of VhGeneTypePropKey:
          last.state = VhGeneTypePropValue
          if last.value.gene_props.has_key(last.key):
            merge_maps(last.value.gene_props[last.key], value)
          else:
            last.value.gene_props[last.key] = value
          break
        of VhMapShortcut:
          discard
        else:
          todo($last.state)
    of VhGeneStart:
      last.state = VhGeneType
      last.value.gene_type = event.value
    of VhGeneType, VhGeneTypeChild:
      last.state = VhGeneTypeChild
      last.value.gene_children.add(event.value)
    of VhGeneTypePropKey:
      last.state = VhGeneTypePropValue
      last.value.gene_props[last.key] = event.value
    of VhGeneTypeChildPropKey:
      last.state = VhGeneTypeChildPropValue
      last.value.gene_props[last.key] = event.value
    of VhGeneTypePropValue, VhGeneTypePropChild, VhGeneTypeChildPropValue:
      last.state = VhGeneTypePropChild
      last.value.gene_children.add(event.value)
    of VhQuote:
      case self.stack.len:
      of 1:
        self.parser.paused = true
        last.state = VhDefault
        last.value = Value(kind: VkQuote, quote: event.value)
      else:
        discard self.stack.pop()
        last = self.stack[^1]
    of VhUnquote:
      case self.stack.len:
      of 1:
        self.parser.paused = true
        last.state = VhDefault
        last.value = Value(kind: VkUnquote, unquote: event.value)
      else:
        discard self.stack.pop()
        last = self.stack[^1]
    of VhDecoratorStart:
      last.state = VhDecoratorFirst
      last.value = new_gene_gene(event.value)
    of VhDecoratorFirst:
      last.value.gene_children.add(event.value)
      self.unwrap()
    else:
      todo($last.state)

proc handle_value*(h: ParseHandler, event: ParseEvent) {.locks: "unknown".} =
  var self = cast[ValueHandler](h)
  # echo "handle_value " & $event & " " & $self.stack.len
  case event.kind:
  of PeStart:
    discard
  of PeStartDocument:
    let value = Value(kind: VkDocument, document: Document())
    # TODO: add value to parent context
    var context = ValueHandlerContext(state: VhDocStart, value: value)
    self.stack.add(context)
  of PeValue:
    self.post_value_callback(event)
  of PeStartVector:
    let value = new_gene_vec()
    # TODO: add value to parent context
    var context = ValueHandlerContext(state: VhVectorStart, value: value)
    self.stack.add(context)
  of PeStartSet:
    let value = new_gene_set()
    # TODO: add value to parent context
    var context = ValueHandlerContext(state: VhSetStart, value: value)
    self.stack.add(context)
  of PeEndVectorOrSet:
    self.unwrap()
  of PeStartMap:
    let value = new_gene_map()
    # TODO: add value to parent context
    var context = ValueHandlerContext(state: VhMapStart, value: value)
    self.stack.add(context)
  of PeMapShortcut:
    let value = new_gene_map()
    # TODO: add value to parent context
    var context = ValueHandlerContext(
      state: VhMapShortcut,
      value: value,
      key: event.key,
    )
    self.stack.add(context)
  of PeEndMap:
    self.unwrap()
  of PeKey:
    var context = self.stack[^1]
    context.key = event.key
    case context.state:
    of VhMapStart, VhMapValue:
      context.state = VhMapKey
    of VhGeneType, VhGeneTypePropValue:
      context.state = VhGeneTypePropKey
    of VhGeneTypeChild:
      context.state = VhGeneTypeChildPropKey
    of VhDocStart, VhDocPropValue:
      context.state = VhDocPropKey
    else:
      todo($context.state)
  of PeStartGene:
    var context = ValueHandlerContext(state: VhGeneStart, value: new_gene_gene())
    self.stack.add(context)
  of PeEndGene:
    self.unwrap()
  of PeQuote:
    var context = ValueHandlerContext(state: VhQuote)
    self.stack.add(context)
  of PeUnquote:
    var context = ValueHandlerContext(state: VhUnquote)
    self.stack.add(context)
  of PeStartDecorator:
    var context = ValueHandlerContext(state: VhDecoratorStart)
    self.stack.add(context)
  of PeEnd:
    discard
  else:
    todo($event)

#################### Parser ######################

proc new_preprocessing_handler*(parser: ptr Parser): PreprocessingHandler =
  PreprocessingHandler(
    parser: parser,
    handle: handle_preprocess,
  )

proc new_value_handler*(parser: ptr Parser): ValueHandler =
  ValueHandler(
    parser: parser,
    handle: handle_value,
  )

proc new_parser*(options: ParseOptions): Parser =
  if not INITIALIZED:
    init()

  result = Parser(
    # document: Document(),
    options: new_options(options),
    references: References(),
  )
  result.handler = new_preprocessing_handler(result.addr)

proc new_parser*(): Parser =
  if not INITIALIZED:
    init()

  result = Parser(
    # document: Document(),
    options: default_options(),
    references: References(),
  )
  result.handler = new_preprocessing_handler(result.addr)

proc non_constituent(c: char): bool =
  result = non_constituents.contains(c)

proc is_macro(c: char): bool =
  result = c.to_int < macros.len and macros[c] != nil

proc is_terminating_macro(c: char): bool =
  result = c != '#' and c != '\'' and is_macro(c)

proc get_macro(ch: char): MacroReader =
  result = macros[ch]

### === ERROR HANDLING UTILS ===

proc err_info(self: Parser): ParseInfo =
  result = (self.line_number, self.get_col_number(self.bufpos))

### === MACRO READERS ===

proc handle_hex_char(c: char, x: var int): bool =
  result = true
  case c
  of '0'..'9': x = (x shl 4) or (ord(c) - ord('0'))
  of 'a'..'f': x = (x shl 4) or (ord(c) - ord('a') + 10)
  of 'A'..'F': x = (x shl 4) or (ord(c) - ord('A') + 10)
  else: result = false

proc parse_escaped_utf16(buf: cstring, pos: var int): int =
  result = 0
  for _ in 0..3:
    if handle_hex_char(buf[pos], result):
      inc(pos)
    else:
      return -1

proc parse_string(self: var Parser, start: char, triple_mode: bool = false): TokenKind =
  result = TkString
  self.str = ""
  var pos = self.bufpos
  while true:
    case self.buf[pos]
    of '\0':
      self.error = ErrQuoteExpected
      break
    of '\'':
      if self.buf[pos] == start:
        inc(pos)
        break
      else:
        add(self.str, self.buf[pos])
        inc(pos)
    of '#':
      if start == '#' and self.buf[pos + 1] in ['<', '{', '[', '(']:
        break
      else:
        add(self.str, self.buf[pos])
        inc(pos)
    of '"':
      if triple_mode:
        if self.buf[pos + 1] == '"' and self.buf[pos + 2] == '"':
          pos = pos + 3
          self.str = self.str.replace(re"^\s*\n", "\n").replace(re"\n\s*$", "\n")
          break
        else:
          inc(pos)
          add(self.str, '"')
      elif start == '#':
        break
      elif self.buf[pos] == start:
        inc(pos)
        break
      else:
        add(self.str, self.buf[pos])
        inc(pos)
    of '\\':
      if start == '\'':
        add(self.str, self.buf[pos])
        inc(pos)
      else:
        case self.buf[pos+1]
        of 'b':
          add(self.str, '\b')
          inc(pos, 2)
        of 'f':
          add(self.str, '\b')
          inc(pos, 2)
        of 'n':
          add(self.str, '\L')
          inc(pos, 2)
        of 'r':
          add(self.str, '\C')
          inc(pos, 2)
        of 't':
          add(self.str, '\t')
          inc(pos, 2)
        of 'u':
          inc(pos, 2)
          var r = parse_escaped_utf16(self.buf, pos)
          if r < 0:
            self.error = ErrInvalidToken
            break
          # deal with surrogates
          if (r and 0xfc00) == 0xd800:
            if self.buf[pos] & self.buf[pos + 1] != "\\u":
              self.error = ErrInvalidToken
              break
            inc(pos, 2)
            var s = parse_escaped_utf16(self.buf, pos)
            if (s and 0xfc00) == 0xdc00 and s > 0:
              r = 0x10000 + (((r - 0xd800) shl 10) or (s - 0xdc00))
            else:
              self.error = ErrInvalidToken
              break
          add(self.str, toUTF8(Rune(r)))
        else:
          add(self.str, self.buf[pos+1])
          inc(pos, 2)
    of '\c':
      pos = lexbase.handleCR(self, pos)
      add(self.str, '\c')
    of '\L':
      pos = lexbase.handleLF(self, pos)
      add(self.str, '\L')
    else:
      add(self.str, self.buf[pos])
      inc(pos)
  self.bufpos = pos

proc read_string(self: var Parser, start: char): Value =
  if start == '"' and self.buf[self.bufpos] == '"' and self.buf[self.bufpos + 1] == '"':
    self.bufpos += 2
    discard self.parse_string(start, true)
  else:
    discard self.parse_string(start)
  if self.error != ErrNone:
    raise new_exception(ParseError, "read_string failure: " & $self.error)
  result = new_gene_string_move(self.str)
  self.str = ""

proc read_string1(self: var Parser): Value =
  self.read_string('\'')

proc read_string2(self: var Parser): Value =
  self.read_string('"')

proc read_quoted(self: var Parser): Value =
  result = Value(kind: VkQuote)
  result.quote = self.read()

proc read_string_interpolation(self: var Parser): Value =
  result = new_gene_gene(new_gene_symbol("#Str"))
  var triple_mode = false
  if self.buf[self.bufpos] == '"' and self.buf[self.bufpos + 1] == '"':
    self.bufpos += 2
    triple_mode = true

  var all_are_strings = true
  while true:
    if self.buf[self.bufpos] == '#':
      self.bufpos.inc()
      case self.buf[self.bufpos]:
      of '<':
        self.bufpos.inc()
        self.skip_block_comment()
        continue

      of '{':
        self.bufpos.inc()
        self.skip_ws()
        if self.buf[self.bufpos] == '^':
          let v = new_gene_map()
          v.map = self.read_map(MkMap)
          result.gene_children.add(v)
          all_are_strings = false
        else:
          let v = self.read()
          if v.kind != VkString:
            all_are_strings = false
          result.gene_children.add(v)
          self.skip_ws()
          self.bufpos.inc()
        continue

      of '(', '[':
        let v = self.read()
        result.gene_children.add(v)
        if v.kind != VkString:
          all_are_strings = false
        continue

      else:
        discard

    discard self.parse_string('#', triple_mode)
    if self.error != ErrNone:
      raise new_exception(ParseError, "read_string_interpolation failure: " & $self.error)
    result.gene_children.add(new_gene_string_move(self.str))
    self.str = ""
    if self.buf[self.bufpos - 1] == '"':
      break

  if all_are_strings:
    var s = ""
    for v in result.gene_children:
      s.add(v.str)
    return new_gene_string_move(s)

proc read_unquoted(self: var Parser): Value =
  # Special logic for %_
  var unquote_discard = false
  if self.buf[self.bufpos] == '_':
    self.bufpos.inc()
    unquote_discard = true
  result = Value(kind: VkUnquote)
  result.unquote = self.read()
  result.unquote_discard = unquote_discard

proc skip_block_comment(self: var Parser) {.gcsafe.} =
  var pos = self.bufpos
  while true:
    case self.buf[pos]
    of '#':
      if self.buf[pos-1] == '>' and self.buf[pos-2] != '>':
        inc(pos)
        break
      else:
        inc(pos)
    of EndOfFile:
      break
    else:
      inc(pos)
  self.bufpos = pos
  self.str = ""

proc skip_comment(self: var Parser) =
  var pos = self.bufpos
  while true:
    case self.buf[pos]
    of '\L':
      pos = lexbase.handleLF(self, pos)
      break
    of '\c':
      pos = lexbase.handleCR(self, pos)
      break
    of EndOfFile:
      break
    else:
      inc(pos)
  self.bufpos = pos

proc read_token(self: var Parser, lead_constituent: bool, chars_allowed: openarray[char]): string =
  var pos = self.bufpos
  var ch = self.buf[pos]
  if lead_constituent and non_constituent(ch):
    raise new_exception(ParseError, "Invalid leading character " & ch)
  else:
    result = ""
    result.add(ch)
  while true:
    inc(pos)
    ch = self.buf[pos]
    if ch == '\\':
      result.add(ch)
      inc(pos)
      ch = self.buf[pos]
      result.add(ch)
    elif ch == EndOfFile or is_space_ascii(ch) or ch == ',' or (is_terminating_macro(ch) and ch notin chars_allowed):
      break
    elif non_constituent(ch):
      raise new_exception(ParseError, "Invalid constituent character: " & ch)
    else:
      result.add(ch)
  self.bufpos = pos

proc read_token(self: var Parser, lead_constituent: bool): string =
  return self.read_token(lead_constituent, [':'])

proc read_character(self: var Parser): Value =
  result = Value(kind: VkChar)
  let token = self.read_token(false)

  case token:
  of "newline":
    result.char = '\n'
  of "space":
    result.char = ' '
  of "tab":
    result.char = '\t'
  of "backspace":
    result.char = '\b'
  of "formfeed":
    result.char = '\f'
  of "return":
    result.char = '\r'
  else:
    if token.len == 1:
      result.char = token[0]
    elif token.runeLen == 1:
      result.rune = token.runeAt(0)
    # elif token.startsWith("\\u"):
    #   # TODO: impl unicode char reading
    #   raise new_exception(ParseError, "Not implemented: reading unicode chars")
    else:
      raise new_exception(ParseError, "Unknown character: " & token)

proc skip_ws(self: var Parser) {.gcsafe.} =
  # commas are whitespace in gene collections
  while true:
    case self.buf[self.bufpos]
    of ' ', '\t', ',':
      inc(self.bufpos)
    of '\c':
      self.bufpos = lexbase.handleCR(self, self.bufpos)
    of '\L':
      self.bufpos = lexbase.handleLF(self, self.bufpos)
    of '#':
      case self.buf[self.bufpos + 1]:
      of ' ', '!', '#', '\r', '\n':
        self.skip_comment()
      of '<':
        self.skip_block_comment()
      else:
        break
    else:
      break

proc match_symbol(s: string): Value =
  var parts: seq[string] = @[]
  var i = 0
  var part = ""
  while i < s.len:
    var ch = s[i]
    i += 1
    case ch:
    of '\\':
      ch = s[i]
      part &= ch
      i += 1
    of '/':
      parts.add(part)
      part = ""
    else:
      part &= ch
  parts.add(part)

  if parts.len > 1:
    return new_gene_complex_symbol(parts)
  else:
    return new_gene_symbol(parts[0])

proc interpret_token(token: string): Value =
  case token
  of "nil":
    return Value(kind: VkNil)
  of "true":
    return new_gene_bool(token)
  of "false":
    return new_gene_bool(token)
  else:
    return match_symbol(token)

proc read_gene_type(self: var Parser): Value =
  var delimiter = ')'
  # the bufpos should be already be past the opening paren etc.
  while true:
    self.skip_ws()
    var pos = self.bufpos
    let ch = self.buf[pos]
    if ch == EndOfFile:
      let msg = "EOF while reading list $# $# $#"
      raise new_exception(ParseError, format(msg, delimiter, self.filename, self.line_number))

    if ch == delimiter:
      # Do not increase position because we need to read other components in
      # inc(pos)
      # p.bufpos = pos
      break

    if is_macro(ch):
      let m = get_macro(ch)
      inc(pos)
      self.bufpos = pos
      result = m(self)
      # if result != nil:
      #   break
    else:
      result = self.read()
      # if result != nil:
      #   break
    break

proc to_keys(self: string): seq[string] =
  # let parts = self.split("^")
  # return parts
  var pos = 0
  var key = ""
  var last: char = EndOfFile
  while pos < self.len:
    var ch = self[pos]
    if ch == '^' and last != '^':
      result.add(key)
      key = ""
    else:
      key.add(ch)
    last = ch
    pos.inc

  result.add(key)

proc read_map(self: var Parser, mode: MapKind): Table[string, Value] {.gcsafe.} =
  var ch: char
  var key: string
  var state = PropState.PropKey

  result = init_table[string, Value]()
  var map = result.addr

  while true:
    self.skip_ws()
    ch = self.buf[self.bufpos]
    if ch == EndOfFile:
      if mode == MkDocument:
        return result
      else:
        raise new_exception(ParseError, "EOF while reading ")
    elif ch == ']' or (mode == MkGene and ch == '}') or (mode == MkMap and ch == ')'):
      raise new_exception(ParseError, "Unmatched delimiter: " & self.buf[self.bufpos])

    case state:
    of PropKey:
      if ch == '^':
        self.bufPos.inc()
        if self.buf[self.bufPos] == '^':
          self.bufPos.inc()
          key = self.read_token(false)
          result[key] = new_gene_bool(true)
        elif self.buf[self.bufPos] == '!':
          self.bufPos.inc()
          key = self.read_token(false)
          result[key] = Value(kind: VkNil)
        else:
          key = self.read_token(false)
          if key.contains('^'):
            let parts = key.to_keys()
            map = result.addr
            for part in parts[0..^2]:
              if map[].has_key(part):
                map = map[][part].map.addr
              else:
                var new_map = new_gene_map()
                map[][part] = new_map
                map = new_map.map.addr
            key = parts[^1]
            case key[0]:
            of '^':
              map[][key[1..^1]] = true
              continue
            of '!':
              map[][key[1..^1]] = false
              continue
            else:
              discard
          state = PropState.PropValue
      elif mode == MkGene or mode == MkDocument:
        # Do not consume ')'
        # if ch == ')':
        #   self.bufPos.inc()
        return
      elif ch == '}':
        self.bufPos.inc()
        return
      else:
        raise new_exception(ParseError, "Expect key at " & $self.bufpos & " but found " & self.buf[self.bufpos])

    of PropState.PropValue:
      if ch == EndOfFile or ch == '^':
        raise new_exception(ParseError, "Expect value for " & key)
      elif mode == MkGene:
        if ch == ')':
          raise new_exception(ParseError, "Expect value for " & key)
      elif ch == '}':
        raise new_exception(ParseError, "Expect value for " & key)
      state = PropState.PropKey

      var value = self.read()
      if map[].has_key(key):
        raise new_exception(ParseError, "Bad input at " & $self.bufpos & " (conflict with property shortcut found earlier.)")
        # if value.kind == VkMap:
        #   for k, v in value.map:
        #     map[][key].map[k] = v
        # else:
        #   raise new_exception(ParseError, "Bad input: mixing map with non-map")
      else:
        map[][key] = value

      map = result.addr

proc read_delimited_list(self: var Parser, delimiter: char, is_recursive: bool): DelimitedListResult {.gcsafe.} =
  # the bufpos should be already be past the opening paren etc.
  var list: seq[Value] = @[]
  var in_gene = delimiter == ')'
  var map_found = false
  var count = 0
  while true:
    self.skip_ws()
    var pos = self.bufpos
    let ch = self.buf[pos]
    if ch == EndOfFile:
      let msg = "EOF while reading list $# $# $#"
      raise new_exception(ParseError, format(msg, delimiter, self.filename, self.line_number))

    if in_gene and ch == '^':
      if map_found:
        let msg = "properties found in wrong place while reading list $# $# $#"
        raise new_exception(ParseError, format(msg, delimiter, self.filename, self.line_number))
      else:
        map_found = true
        result.map = self.read_map(MkGene)
        continue

    if ch == delimiter:
      inc(pos)
      self.bufpos = pos
      break

    if is_macro(ch):
      let m = get_macro(ch)
      inc(pos)
      self.bufpos = pos
      let node = m(self)
      if node != nil:
        inc(count)
        if self.options["debug"]: echo $node, "\n"
        list.add(node)
    else:
      let node = self.read()
      if node != nil:
        inc(count)
        if self.options["debug"]: echo $node, "\n"
        list.add(node)

  result.list = list

proc add_line_col(self: var Parser, node: var Value) =
  discard
  # node.line = self.line_number
  # node.column = self.getColNumber(self.bufpos)

proc read_gene(self: var Parser): Value {.gcsafe.} =
  result = new_gene_gene()
  #echo "line ", getCurrentLine(p), "lineno: ", p.line_number, " col: ", getColNumber(p, p.bufpos)
  #echo $get_current_line(p) & " LINENO(" & $p.line_number & ")"
  self.add_line_col(result)
  result.gene_type = self.read_gene_type()
  var result_list = self.read_delimited_list(')', true)
  result.gene_props = result_list.map
  result.gene_children = result_list.list
  # if not result.gene_type.is_nil() and result.gene_type.kind == VkSymbol:
  #   if handlers.has_key(result.gene_type.str):
  #     let handler = handlers[result.gene_type.str]
  #     return handler(self, result)

proc read_map(self: var Parser): Value {.gcsafe.} =
  result = Value(kind: VkMap)
  let map = self.read_map(MkMap)
  result.map = map

proc read_vector(self: var Parser): Value {.gcsafe.} =
  result = Value(kind: VkVector)
  let list_result = self.read_delimited_list(']', true)
  result.vec = list_result.list

# proc read_set(self: var Parser): Value =
#   result = Value(
#     kind: VkSet,
#     set: HashSet[Value](),
#   )
#   let list_result = self.read_delimited_list(']', true)
#   for item in list_result.list:
#     result.set.incl(item)

proc read_regex(self: var Parser): Value =
  var pos = self.bufpos
  var flags: set[RegexFlag]
  while true:
    case self.buf[pos]
    of EndOfFile:
      self.error = ErrRegexEndExpected
    of '/':
      inc(pos)
      if self.buf[pos] == 'i':
        inc(pos)
        flags.incl(RfIgnoreCase)
        if self.buf[pos] == 'm':
          inc(pos)
          flags.incl(RfMultiLine)
      elif self.buf[pos] == 'm':
        inc(pos)
        flags.incl(RfMultiLine)
        if self.buf[pos] == 'i':
          inc(pos)
          flags.incl(RfIgnoreCase)
      break
    of '\\':
      case self.buf[pos+1]
      of '\\', '/':
        add(self.str, self.buf[pos+1])
        inc(pos, 2)
      of 'b':
        add(self.str, '\b')
        inc(pos, 2)
      of 'f':
        add(self.str, '\b')
        inc(pos, 2)
      of 'n':
        add(self.str, '\L')
        inc(pos, 2)
      of 'r':
        add(self.str, '\C')
        inc(pos, 2)
      of 't':
        add(self.str, '\t')
        inc(pos, 2)
      of 'u':
        inc(pos, 2)
        var r = parse_escaped_utf16(self.buf, pos)
        if r < 0:
          self.error = ErrInvalidToken
          break
        # deal with surrogates
        if (r and 0xfc00) == 0xd800:
          if self.buf[pos] & self.buf[pos + 1] != "\\u":
            self.error = ErrInvalidToken
            break
          inc(pos, 2)
          var s = parse_escaped_utf16(self.buf, pos)
          if (s and 0xfc00) == 0xdc00 and s > 0:
            r = 0x10000 + (((r - 0xd800) shl 10) or (s - 0xdc00))
          else:
            self.error = ErrInvalidToken
            break
        add(self.str, toUTF8(Rune(r)))
      else:
        # don't bother with the Error
        add(self.str, self.buf[pos])
        inc(pos)
    of '\c':
      pos = lexbase.handleCR(self, pos)
      add(self.str, '\c')
    of '\L':
      pos = lexbase.handleLF(self, pos)
      add(self.str, '\L')
    else:
      add(self.str, self.buf[pos])
      inc(pos)
  self.bufpos = pos
  result = new_gene_regex(self.str, flags)

proc read_unmatched_delimiter(self: var Parser): Value =
  raise new_exception(ParseError, "Unmatched delimiter: " & self.buf[self.bufpos])

proc read_dispatch(self: var Parser): Value =
  let ch = self.buf[self.bufpos]
  let m = dispatch_macros[ch]
  if m == nil:
    self.bufpos -= 1
    var token = self.read_token(false)
    result = interpret_token(token)
  else:
    self.bufpos += 1
    result = m(self)

proc init_macro_array() =
  macros['\''] = read_string1
  macros['"'] = read_string2
  macros[':'] = read_quoted
  # macros['\\'] = read_character
  # macros['`'] = read_quasi_quoted
  macros['%'] = read_unquoted
  macros['#'] = read_dispatch
  macros['('] = read_gene
  macros['{'] = read_map
  macros['['] = read_vector
  macros[')'] = read_unmatched_delimiter
  macros[']'] = read_unmatched_delimiter
  macros['}'] = read_unmatched_delimiter

proc handle_file(self: var Parser, value: Value): Value =
  result = Value(kind: VkFile)
  result.file_name = value.gene_children[0].str
  result.file_content = value.gene_children[1]

proc handle_dir(self: var Parser, value: Value): Value =
  result = Value(kind: VkDirectory)
  result.dir_name = value.gene_children[0].str
  for child in value.gene_children[1..^1]:
    var child_name: string
    case child.kind:
    of VkFile:
      child_name = child.file_name
      child.file_parent = result
    of VkDirectory:
      child_name = child.dir_name
      child.dir_parent = result
    of VkArchiveFile:
      child_name = child.arc_file_name
      child.arc_file_parent = result
    else:
      not_allowed("unknown child " & $child)
    result.dir_members[child_name] = child

proc handle_arc(self: var Parser, value: Value): Value =
  result = Value(kind: VkArchiveFile)
  result.arc_file_name = value.gene_children[0].str
  for child in value.gene_children[1..^1]:
    var child_name: string
    case child.kind:
    of VkFile:
      child_name = child.file_name
      child.file_parent = result
    of VkDirectory:
      child_name = child.dir_name
      child.dir_parent = result
    of VkArchiveFile:
      child_name = child.arc_file_name
      child.arc_file_parent = result
    else:
      not_allowed("unknown child " & $child)
    result.arc_file_members[child_name] = child

proc handle_set(self: var Parser, value: Value): Value =
  if value.gene_children[0].is_symbol("debug"):
    self.options["debug"] = value.gene_children[1].bool
  else:
    todo("#Set " & $value.gene_children[0])

proc handle_ignore(self: var Parser, value: Value): Value =
  Ignore

proc handle_reference(self: var Parser, value: Value): Value =
  let name = value.gene_children[0].str
  if self.references.has_key(name):
    raise new_exception(ParseError, "Duplicate reference: " & name)
  else:
    let target = RefTarget(
      name: name,
      value: value.gene_children[1],
      registry: self.references,
    )
    result = Value(kind: VkRefTarget, ref_target: target)
    self.references[name] = result

proc init_handlers() =
  handlers["#Ref"] = handle_reference
  handlers["#File"] = handle_file
  handlers["#Dir"] = handle_dir
  handlers["#Gar"] = handle_arc
  handlers["#Set"] = handle_set
  handlers["#Ignore"] = handle_ignore

proc init*() =
  if INITIALIZED:
    return

  INITIALIZED = true
  DEFAULT_UNITS = {
    "m": new_gene_int(60),        # m  = minute
    "s": new_gene_int(1),         # s  = second (default)
    "ms": new_gene_float(0.001),  # ms = millisecond
    "ns": new_gene_float(1e-9),   # ns = nanosecond
  }.to_table()

  HEX = {
    '0': 0u8, '1': 1u8, '2': 2u8, '3': 3u8, '4': 4u8,
    '5': 5u8, '6': 6u8, '7': 7u8, '8': 8u8, '9': 9u8,
    'a': 10u8, 'b': 11u8, 'c': 12u8, 'd': 13u8, 'e': 14u8, 'f': 15u8,
    'A': 10u8, 'B': 11u8, 'C': 12u8, 'D': 13u8, 'E': 14u8, 'F': 15u8,
  }.to_table()

  Ignore = Value(kind: VkCustom, custom: CustomValue())

  DATE_FORMAT = init_time_format("yyyy-MM-dd")
  DATETIME_FORMAT = init_time_format("yyyy-MM-dd'T'HH:mm:sszzz")

  init_macro_array()
  init_handlers()

proc open*(self: var Parser, input: Stream, filename: string) =
  lexbase.open(self, input)
  self.filename = filename
  self.str = ""

proc open*(self: var Parser, input: Stream) =
  self.open(input, "<input>")

proc open*(self: var Parser, code: string, filename: string) =
  self.open(new_string_stream(code), filename)

proc open*(self: var Parser, code: string) =
  self.open(new_string_stream(code), "<input>")

proc close*(self: var Parser) {.inline.} =
  lexbase.close(self)

# proc get_line(self: Parser): int {.inline.} =
#   result = self.line_number

# proc get_column(self: Parser): int {.inline.} =
#   result = self.get_col_number(self.bufpos)

# proc get_filename(self: Parser): string =
#   result = self.filename

proc parse_bin(self: var Parser): Value =
  var bytes: seq[uint8] = @[]
  var byte: uint8 = 0
  var size: uint = 0
  while self.buf[self.bufpos] in ['0', '1', '~']:
    if self.buf[self.bufpos] == '~':
      self.bufpos += 1
      self.skip_ws()
      continue

    size += 1
    byte = byte.shl(1)
    if self.buf[self.bufpos] == '1':
      byte = byte.or(1)
    if size mod 8 == 0:
      bytes.add(byte)
      byte = 0
    self.bufpos += 1
  if size mod 8 != 0:
    # Add last partial byte
    bytes.add(byte)

  if size == 0:
    not_allowed("parse_bin: input length is zero.")
  elif size <= 8:
    return Value(
      kind: VkByte,
      byte: bytes[0],
      byte_bit_size: size,
    )
  else:
    return Value(
      kind: VkBin,
      bin: bytes,
      bin_bit_size: size,
    )

proc parse_hex(self: var Parser): Value =
  var bytes: seq[uint8] = @[]
  var byte: uint8 = 0
  var size: uint = 0
  var ch = self.buf[self.bufpos]
  while ch in '0'..'9' or ch in 'A'..'F' or ch in 'a'..'f' or ch == '~':
    if ch == '~':
      self.bufpos += 1
      self.skip_ws()
      ch = self.buf[self.bufpos]
      continue

    size += 4
    byte = byte.shl(4)
    byte += HEX[ch]
    if size mod 8 == 0:
      bytes.add(byte)
      byte = 0
    self.bufpos += 1
    ch = self.buf[self.bufpos]
  if size mod 8 != 0:
    # Add last partial byte
    bytes.add(byte)

  if size == 0:
    not_allowed("parse_bin: input length is zero.")
  elif size <= 8:
    return Value(
      kind: VkByte,
      byte: bytes[0],
      byte_bit_size: size,
    )
  else:
    return Value(
      kind: VkBin,
      bin: bytes,
      bin_bit_size: size,
    )

proc add(self: var seq[uint8], str: string) =
  for c in str:
    self.add(uint8(c))

proc parse_base64(self: var Parser): Value =
  var bytes: seq[uint8] = @[]
  var ch = self.buf[self.bufpos]
  var s = ""
  while ch in '0'..'9' or ch in 'A'..'Z' or ch in 'a'..'z' or ch in ['+', '/', '=', '~']:
    if ch == '~':
      self.bufpos += 1
      self.skip_ws()
      ch = self.buf[self.bufpos]
      continue

    s &= ch
    self.bufpos += 1
    ch = self.buf[self.bufpos]
    if s.len == 4:
      echo s
      bytes.add(decode(s))
      s = ""

  if s.len > 0:
    bytes.add(decode(s))

  return Value(
    kind: VkBin,
    bin: bytes,
    bin_bit_size: uint(bytes.len * 8),
  )

proc parse_number(self: var Parser): TokenKind =
  result = TokenKind.TkEof
  var pos = self.bufpos
  if (self.buf[pos] == '-') or (self.buf[pos] == '+'):
    add(self.str, self.buf[pos])
    inc(pos)
  if self.buf[pos] == '.':
    add(self.str, "0.")
    inc(pos)
    result = TkFloat
  else:
    result = TkInt
    while self.buf[pos] in Digits:
      add(self.str, self.buf[pos])
      inc(pos)
    if self.buf[pos] == '.':
      add(self.str, '.')
      inc(pos)
      result = TkFloat
  # digits after the dot
  while self.buf[pos] in Digits:
    add(self.str, self.buf[pos])
    inc(pos)
  if self.buf[pos] in {'E', 'e'}:
    add(self.str, self.buf[pos])
    inc(pos)
    result = TkFloat
    if self.buf[pos] in {'+', '-'}:
      add(self.str, self.buf[pos])
      inc(pos)
    while self.buf[pos] in Digits:
      add(self.str, self.buf[pos])
      inc(pos)
  elif self.buf[pos] in {'a' .. 'z', 'A' .. 'Z'}:
    var num = self.str
    self.str = ""
    self.bufpos = pos
    var unit = ""
    while true:
      add(unit, self.buf[pos])
      inc(pos)
      if self.buf[pos] notin {'a' .. 'z', 'A' .. 'Z'}:
        break
    self.bufpos = pos
    self.num_with_units.add((result, num, unit))
    if self.buf[pos] in {'.', '0' .. '9'}: # handle something like 1m30s
      discard self.parse_number()
    result = TkNumberWithUnit
  self.bufpos = pos

proc read_number(self: var Parser): Value =
  if self.buf[self.bufpos] == '0':
    let ch = self.buf[self.bufpos + 1]
    case ch:
    of '!':
      self.bufpos += 2
      return self.parse_bin()
    of '*':
      self.bufpos += 2
      return self.parse_hex()
    of '#':
      self.bufpos += 2
      return self.parse_base64()
    else:
      discard

  var num_result = self.parse_number()
  case num_result
  of TkEof:
    raise new_exception(ParseError, "EOF while reading")
  of TkInt:
    var c = self.buf[self.bufpos]
    case c:
    of '-':
      var s = self.str & self.read_token(false, [':'])
      if s.contains(':'):
        var date = parse(s, DATETIME_FORMAT, utc())
        result = new_gene_datetime(date)
      else:
        var date = parse(s, DATE_FORMAT, utc())
        result = new_gene_date(date)
    of ':':
      var s = self.str & self.read_token(false, [':'])
      var parts = s.split(":")
      var hour = parts[0].parse_int()
      var min = parts[1].parse_int()
      var sec = parts[2].parse_int()
      result = new_gene_time(hour, min, sec)
    of '/':
      if not isDigit(self.buf[self.bufpos+1]):
        let e = err_info(self)
        raise new_exception(ParseError, "Error reading a ratio: " & $e)
      var numerator = new_gene_int(self.str)
      inc(self.bufpos)
      self.str = ""
      var denom_tok = parse_number(self)
      if denom_tok == TkInt:
        var denom = new_gene_int(self.str)
        result = new_gene_ratio(numerator.int, denom.int)
      else:
        raise new_exception(ParseError, "Error reading a ratio: " & self.str)
    else:
      result = new_gene_int(self.str)
  of TkFloat:
    result = new_gene_float(self.str)
  of TkError:
    raise new_exception(ParseError, "Error reading a number: " & self.str)
  of TkNumberWithUnit:
    result = new_gene_int()
    for (kind, num, unit) in self.num_with_units:
      var unit_base = self.options.units[unit]
      if kind == TkInt:
        if result.kind == VkInt:
          if unit_base.kind == VkInt:
            result.int += num.parse_int() * unit_base.int.int()
          else:
            result = new_gene_float(result.int.to_float())
            result.float += num.parse_int().to_float() * unit_base.float
        else:
          result.float += num.parse_int().to_float() * unit_base.float
      else:
        if result.kind == VkInt:
          result = new_gene_float(result.int.to_float())
        if unit_base.kind == VkInt:
          result.float += num.parse_float() * unit_base.int.to_float()
        else:
          result.float += num.parse_float() * unit_base.float
  else:
    raise new_exception(ParseError, "Error reading a number (?): " & self.str)

proc read*(self: var Parser): Value =
  set_len(self.str, 0)
  self.skip_ws()
  let ch = self.buf[self.bufpos]
  var token: string
  case ch
  of EndOfFile:
    let position = (self.line_number, self.get_col_number(self.bufpos))
    raise new_exception(ParseEofError, "EOF while reading " & $position)
  of '0'..'9':
    return read_number(self)
  elif is_macro(ch):
    let m = macros[ch] # save line:col metadata here?
    inc(self.bufpos)
    result = m(self)
    if result == Ignore:
      result = self.read()
    return result
  elif ch in ['+', '-']:
    if isDigit(self.buf[self.bufpos + 1]):
      return self.read_number()
    else:
      token = self.read_token(false)
      result = interpret_token(token)
      if result == Ignore:
        result = self.read()
      return result

  token = self.read_token(true)
  result = interpret_token(token)
  if result == Ignore:
    result = self.read()

proc advance*(self: var Parser) =
  while not self.paused:
    set_len(self.str, 0)
    if self.in_str_interpolation:
      let ch = self.buf[self.bufpos]
      case ch:
      of '"':
        inc(self.bufpos)
        self.in_str_interpolation = false
        self.handler.do_handle(ParseEvent(kind: PeEndStrInterpolation))
        continue
      of '#':
        let ch2 = self.buf[self.bufpos + 1]
        case ch2:
        of '{':
          inc(self.bufpos, 2)
          self.handler.do_handle(ParseEvent(kind: PeStartStrMap))
          continue
        of '[':
          inc(self.bufpos, 2)
          self.handler.do_handle(ParseEvent(kind: PeStartStrVector))
          continue
        # of '(':
        #   inc(self.bufpos, 2)
        #   self.handler.do_handle(ParseEvent(kind: PeStartStrGene))
        # of '<':
        #   self.skip_block_comment()
        else:
          discard
      else:
        discard

      discard self.parse_string('#')
      if self.str.len > 0:
        var event = ParseEvent(
          kind: PeValue,
          value: self.str,
        )
        self.handler.do_handle(event)

      continue

    self.skip_ws()
    let ch = self.buf[self.bufpos]
    case ch
    of EndOfFile:
      self.handler.do_handle(ParseEvent(kind: PeEnd))
      self.paused = true
      self.done = true
      break

    of '0'..'9':
      var event = ParseEvent(
        kind: PeValue,
        value: self.read_number(),
      )
      self.handler.do_handle(event)
    of '+', '-':
      if isDigit(self.buf[self.bufpos + 1]):
        var event = ParseEvent(
          kind: PeValue,
          value: self.read_number(),
        )
        self.handler.do_handle(event)
      else:
        var event = ParseEvent(
          kind: PeToken,
          token: self.read_token(false),
        )
        self.handler.do_handle(event)

    of '\'', '"':
      inc(self.bufpos)
      var event = ParseEvent(
        kind: PeValue,
        value: self.read_string(ch),
      )
      self.handler.do_handle(event)

    of '\\':
      inc(self.bufpos)
      let ch2 = self.buf[self.bufpos]
      var value: Value
      case ch2:
      of '\'', '"':
        self.bufpos.inc()
        discard self.parse_string(ch2)
        if self.error != ErrNone:
          raise new_exception(ParseError, "read_string failure: " & $self.error)
        value = new_gene_symbol(self.str)
      else:
        value = self.read_character()
      var event = ParseEvent(
        kind: PeValue,
        value: value,
      )
      self.handler.do_handle(event)

    of '[':
      inc(self.bufpos)
      self.handler.do_handle(ParseEvent(kind: PeStartVector))
    of ']':
      inc(self.bufpos)
      self.handler.do_handle(ParseEvent(kind: PeEndVectorOrSet))

    of '{':
      inc(self.bufpos)
      self.handler.do_handle(ParseEvent(kind: PeStartMap))
    of '}':
      inc(self.bufpos)
      self.handler.do_handle(ParseEvent(kind: PeEndMap))

    of '(':
      inc(self.bufpos)
      self.handler.do_handle(ParseEvent(kind: PeStartGene))
    of ')':
      inc(self.bufpos)
      self.handler.do_handle(ParseEvent(kind: PeEndGene))

    of '^':
      var event = ParseEvent(
        kind: PeToken,
        token: self.read_token(false),
      )
      self.handler.do_handle(event)

    of '#':
      inc(self.bufpos)
      let ch2 = self.buf[self.bufpos]
      case ch2:
      of '"':
        inc(self.bufpos)
        self.handler.do_handle(ParseEvent(kind: PeStartStrInterpolation))
        discard self.parse_string('#')
        if self.str.len > 0:
          var event = ParseEvent(
            kind: PeValue,
            value: self.str,
          )
          self.handler.do_handle(event)

      of '/':
        inc(self.bufpos)
        var event = ParseEvent(
          kind: PeValue,
          value: self.read_regex(),
        )
        self.handler.do_handle(event)
      of '[':
        inc(self.bufpos)
        self.handler.do_handle(ParseEvent(kind: PeStartSet))
      of '@':
        inc(self.bufpos)
        self.handler.do_handle(ParseEvent(kind: PeStartDecorator))
      else:
        todo("#" & $ch2)

    of ':':
      inc(self.bufpos)
      self.handler.do_handle(ParseEvent(kind: PeQuote))
    of '%':
      inc(self.bufpos)
      self.handler.do_handle(ParseEvent(kind: PeUnquote))

    elif is_macro(ch):
      todo()

    else:
      var event = ParseEvent(
        kind: PeToken,
        token: self.read_token(false),
      )
      self.handler.do_handle(event)

proc read_first*(self: var Parser): Value =
  let value_handler = new_value_handler(self.addr)
  self.handler.next = value_handler
  self.handler.do_handle(ParseEvent(kind: PeStart))
  self.advance()
  result = value_handler.stack[0].value

proc read*(self: var Parser, buffer: string): Value =
  var s = new_string_stream(buffer)
  self.open(s, "<input>")
  defer: self.close()
  result = self.read_first()

proc read_all*(self: var Parser, buffer: string): seq[Value] =
  var s = new_string_stream(buffer)
  self.open(s, "<input>")
  defer: self.close()
  let value_handler = new_value_handler(self.addr)
  self.handler.next = value_handler
  self.handler.do_handle(ParseEvent(kind: PeStart))
  while not self.done:
    self.paused = false
    self.advance()
    if value_handler.stack.len > 0:
      result.add(value_handler.stack.pop().value)

proc read_document*(self: var Parser, buffer: string): Document =
  self.mode = PmDocument
  var s = new_string_stream(buffer)
  self.open(s, "<input>")
  defer: self.close()

  let value_handler = new_value_handler(self.addr)
  self.handler.next = value_handler
  self.handler.do_handle(ParseEvent(kind: PeStart))
  self.advance()
  result = value_handler.stack[0].value.document

proc read*(buffer: string): Value =
  var parser = new_parser()
  parser.read(buffer)

proc read_all*(buffer: string): seq[Value] =
  var parser = new_parser()
  return parser.read_all(buffer)

proc read_document*(buffer: string): Document =
  var parser = new_parser()
  return parser.read_document(buffer)

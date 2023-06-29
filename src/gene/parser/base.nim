# Credit:
# The parser and basic data types are built on top of EDN Parser[1] that is
# created by Roland Sadowski.
# 1. https://github.com/rosado/edn.nim

import lexbase, streams, strutils, unicode, tables, sets, times, nre, base64

import ../types

type
  ParseError* = object of CatchableError
  ParseEofError* = object of ParseError

  ParseMode* = enum
    PmDefault
    PmDocument
    PmStream
    PmFirst

  # Each format may have multiple versions and take additional options
  InputFormat* = enum
    IfGene        # Default
    IfGeni        # Gene with indentation
    # IfJson      # Gene data in JSON format, Gene type is encoded as a special JSON object.
    # IfBinary

  ParseOptions* {.acyclic.} = ref object
    parent*: ParseOptions
    data*: Table[string, Value]
    units*: Table[string, Value]

  # Symbols with special characters:
  #   Use \ to escape them (including the first character)
  #   E.g. \(abc\) = a symbol with name "(abc)"
  ParseState* = enum
    PsDefault
    PsSymbol                # After the first character of a symbol
    PsString                # "..."
    PsString3               # """..."""
    PsStrInterpolation      # #"..."
    PsStrInterpolation3     # #"""..."""
    PsCharacter             # '...': 'n', '\n'
    PsNumber                # 123, 123.456, 123.456e+10, 123.456e-10, +123, -123, -1/5, 1_000_000
                            # 10min, 10m20s
    PsBinary                # #=010101, #=010101~ 010101
                            # #=[BINARY DATA] (white spaces are allowed inside the brackets)
                            # #+1234567890abcdef, #+1234567890ABCDEF, #+1234~ 5678
                            # #+[HEX DATA]
                            # #*[BASE64 DATA]
    PsDate                  # 2019-01-01
    PsTime                  # 10:00(hour:minute) 10:20:30(hour:minute:second) 10:20:30EDT 10:20:30-5:00
    PsDateTime              # 2019-01-01T10:20:30.123+08:00
    # PsHereDoc               # #-XYZ...XYZ, #=XYZ...XYZ
    # PsLineComment           # # ..., #!...
    # PsComment               # #<...>#

  Parser* = object of BaseLexer
    mode*: ParseMode
    format*: InputFormat
    options*: ParseOptions
    filename*: string
    state*: ParseState
    str*: string
    num_with_units*: seq[(TokenKind, string, string)] # token kind + number + unit
    token_kind*: TokenKind
    error*: ParseErrorKind
    references*: References
    done*: bool
    paused*: bool
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
    PeStartNumber     # start of data that starts with '0'-'9', or '+' and '-' that is followed with '0'-'9'.
    PeNumber          # [0-9\.]+, the lexer may choose to send multiple PeNumber events for a single number.
    PeNumberToken     # [a-zA-Z\-\_\:\.\/]+ that is immediately after a number.
                      # Please note that not all characters accepted by PeToken are accepted by PeNumberToken.
    PeEndNumber       # sent when a whitespace, a non-token character etc is encountered
    PeStartStrInterpolation   # #", #"""
    PeStartStrValue           # #{
    PeStartStrGene            # #(
    PeStartStrComment         # #<
    PeEndStrInterpolation     # ", """
    PeQuote
    PeUnquote
    PeStartDecorator  # processed by the PreprocessingHandler
    PeNewLine
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
    of PeToken, PeNumberToken:
      token*: string
    of PeComment, PeDocumentComment:
      comment*: string
    of PeError:
      error_code*: string
      error_message*: string
    of PeStartNumber:
      sign*: string # "+" or "-" or ""
    of PeNumber:
      number*: string
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

const non_constituents: seq[char] = @[]

var INITIALIZED* {.threadvar.}: bool
var DEFAULT_UNITS {.threadvar.}: Table[string, Value]
var HEX {.threadvar.}: Table[char, uint8]
var DATE_FORMAT {.threadvar.}: TimeFormat
var DATETIME_FORMAT {.threadvar.}: TimeFormat

#################### Interfaces ##################

proc init*() {.gcsafe.}
proc keys*(self: ParseOptions): HashSet[string]
proc `[]`*(self: ParseOptions, name: string): Value
proc unit_keys*(self: ParseOptions): HashSet[string]
proc `unit`*(self: ParseOptions, name: string): Value
proc skip_ws(self: var Parser) {.gcsafe.}

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

proc merge_maps*(first, second: Value) =
  if first.kind != VkMap or second.kind != VkMap:
    raise newException(ValueError, "merge_map: both values must be maps")
  for k, v in second.map:
    if first.map.has_key(k):
      raise newException(ValueError, "merge_map: key already exists: " & $k)
    first.map[k] = v

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

template do_handle*(self: ParseHandler, event: ParseEvent) =
  self.handle(self, event)

#################### Parser ######################

proc non_constituent(c: char): bool =
  result = non_constituents.contains(c)

proc is_terminating_macro(c: char): bool =
  result = c != '#' and c != '\'' and c in ['#', '\'', '(', ')', '{', '}', '[', ']']

proc err_info(self: Parser): ParseInfo =
  result = (self.line_number, self.get_col_number(self.bufpos))

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

proc skip_comment(self: var Parser) =
  var pos = self.bufpos
  while true:
    case self.buf[pos]
    of '\c': # \r
      break
    of '\L': # \n
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

proc skip_ws(self: var Parser) {.gcsafe.} =
  # commas are whitespace in gene collections
  {.cast(gcsafe).}:
    while true:
      case self.buf[self.bufpos]
      of ' ', '\t', ',':
        inc(self.bufpos)
      of '\c': # \r
        self.bufpos = lexbase.handleCR(self, self.bufpos)
        if self.format == IfGeni:
          self.handler.do_handle(ParseEvent(kind: PeNewLine))
          break
      of '\L': # \n
        self.bufpos = lexbase.handleLF(self, self.bufpos)
        if self.format == IfGeni:
          self.handler.do_handle(ParseEvent(kind: PeNewLine))
          break
      of '#':
        case self.buf[self.bufpos + 1]:
        of ' ':
          self.skip_comment()
        of '!': # Treat #!shebang line as a comment for now.
          self.skip_comment()
        of '\c': # \r
          inc(self.bufpos)
          continue
        of '\L': # \n
          inc(self.bufpos)
          continue
        of '<':
          self.skip_block_comment()
        else:
          break
      else:
        break

proc read_regex(self: var Parser): Value =
  var pos = self.bufpos
  var str = ""
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
        str.add(self.buf[pos+1])
        inc(pos, 2)
      of 'b':
        str.add('\b')
        inc(pos, 2)
      of 'f':
        str.add('\b')
        inc(pos, 2)
      of 'n':
        str.add('\L')
        inc(pos, 2)
      of 'r':
        str.add('\C')
        inc(pos, 2)
      of 't':
        str.add('\t')
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
        str.add(toUTF8(Rune(r)))
      else:
        # don't bother with the Error
        str.add(self.buf[pos])
        inc(pos)
    of '\c':
      pos = lexbase.handleCR(self, pos)
      str.add('\c')
    of '\L':
      pos = lexbase.handleLF(self, pos)
      str.add('\L')
    else:
      str.add(self.buf[pos])
      inc(pos)
  self.bufpos = pos
  result = new_gene_regex(str, flags)

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

  DATE_FORMAT = init_time_format("yyyy-MM-dd")
  DATETIME_FORMAT = init_time_format("yyyy-MM-dd'T'HH:mm:sszzz")

  # init_macro_array()

proc open*(self: var Parser, input: Stream, filename: string) =
  lexbase.open(self, input)
  self.filename = filename

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
  self.str = ""
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

proc advance*(self: var Parser) =
  var str = ""
  while not self.paused:
    # echo "advance " & $self.state
    var ch = self.buf[self.bufpos]
    case self.state:
    of PsString, PsString3:
      str = ""
      var pos = self.bufpos
      while true:
        case self.buf[pos]
        of EndOfFile:
          self.done = true
          self.handler.do_handle(ParseEvent(kind: PeError, error_message: "EOF while reading string"))
          break
        of '"':
          if self.state == PsString3:
            if self.buf[pos + 1] == '"' and self.buf[pos + 2] == '"':
              inc(pos, 3)
              self.state = PsDefault
              str = str.replace(re"^\s*\n", "\n").replace(re"\n\s*$", "\n")
              self.handler.do_handle(ParseEvent(kind: PeValue, value: new_gene_string(str)))
              break
            else:
              inc(pos)
              str.add('"')
          else:
            inc(pos)
            self.state = PsDefault
            self.handler.do_handle(ParseEvent(kind: PeValue, value: new_gene_string(str)))
            break
        of '\\':
          case self.buf[pos+1]
          of 'b':
            str.add('\b')
            inc(pos, 2)
          of 'f':
            str.add('\f')
            inc(pos, 2)
          of 'n':
            str.add('\L')
            inc(pos, 2)
          of 'r':
            str.add('\C')
            inc(pos, 2)
          of 't':
            str.add('\t')
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
            str.add(toUTF8(Rune(r)))
          else:
            str.add(self.buf[pos+1])
            inc(pos, 2)
        of '\c':
          pos = lexbase.handleCR(self, pos)
          str.add('\c')
        of '\L':
          pos = lexbase.handleLF(self, pos)
          str.add('\L')
        else:
          str.add(self.buf[pos])
          inc(pos)
      self.bufpos = pos

    of PsStrInterpolation, PsStrInterpolation3:
      case ch:
      of '"':
        if self.state == PsStrInterpolation:
          inc(self.bufpos)
          self.state = PsDefault
          if str.len > 0:
            var event = ParseEvent(
              kind: PeValue,
              value: str,
            )
            self.handler.do_handle(event)
            str = ""

          self.handler.do_handle(ParseEvent(kind: PeEndStrInterpolation))
          continue
        elif self.buf[self.bufpos + 1] == '"' and self.buf[self.bufpos + 2] == '"':
          inc(self.bufpos, 3)
          self.state = PsDefault
          if str.len > 0:
            var event = ParseEvent(
              kind: PeValue,
              value: str,
            )
            self.handler.do_handle(event)
            str = ""

          self.handler.do_handle(ParseEvent(kind: PeEndStrInterpolation))
          continue

      of '#':
        let ch2 = self.buf[self.bufpos + 1]
        case ch2:
        of '{':
          inc(self.bufpos, 2)
          if str.len > 0:
            var event = ParseEvent(
              kind: PeValue,
              value: str,
            )
            self.handler.do_handle(event)
            str = ""

          self.handler.do_handle(ParseEvent(kind: PeStartStrValue))
          continue
        of '(':
          inc(self.bufpos, 2)
          if str.len > 0:
            var event = ParseEvent(
              kind: PeValue,
              value: str,
            )
            self.handler.do_handle(event)
            str = ""

          self.handler.do_handle(ParseEvent(kind: PeStartStrGene))
          continue
        of '<':
          if str.len > 0:
            var event = ParseEvent(
              kind: PeValue,
              value: str,
            )
            self.handler.do_handle(event)
            str = ""

          self.skip_block_comment()
          continue
        else:
          discard

      else:
        discard

      inc(self.bufpos)
      str.add(ch)

    else:
      self.skip_ws()
      ch = self.buf[self.bufpos]
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

      of '"':
        if self.buf[self.bufpos + 1] == '"' and self.buf[self.bufpos + 2] == '"':
          self.state = PsString3
          inc(self.bufpos, 3)
        else:
          self.state = PsString
          inc(self.bufpos)

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
          self.handler.do_handle(ParseEvent(kind: PeStartStrInterpolation))
          if self.buf[self.bufpos + 1] == '"' and self.buf[self.bufpos + 2] == '"':
            self.state = PsStrInterpolation3
            inc(self.bufpos, 3)
          else:
            self.state = PsStrInterpolation
            inc(self.bufpos)
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

      else:
        var event = ParseEvent(
          kind: PeToken,
          token: self.read_token(false),
        )
        self.handler.do_handle(event)

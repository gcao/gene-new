import tables

import ../types
import ./base

type
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
    PhStrValueStart
    # PhStrInterpolationString      # #"..."
    # PhStrInterpolationMapOrValue  # #{a}
    # PhStrInterpolationGene        # #(...)
    # PhStrInterpolationComment     # #<...>#

    # PhNumberStart
    # PhNumber
    # PhNumberToken
    # PhNumberEnd

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

template send(self: PreprocessingHandler, event: ParseEvent, value: Value) =
  if event.is_nil:
    self.next.do_handle(ParseEvent(kind: PeValue, value: value))
  else:
    self.next.do_handle(event)

proc unwrap(self: PreprocessingHandler, event: ParseEvent, value: Value) =
  if self.stack.len == 0:
    self.send(event, value)
  else:
    var last = self.stack[^1]
    case last.state:
    of PhMapKey:
      last.state = PhMapValue
      if last.defer:
        last.value.map[last.key] = value
      else:
        self.send(event, value)
    of PhStrInterpolation:
      last.value.gene_children.add(value)
      self.parser.state = PsStrInterpolation
    of PhStrValueStart:
      if last.value.is_nil:
        last.value = value
      else:
        not_allowed()
    of PhGeneStart:
      last.state = PhGeneType
      if last.defer:
        last.value.gene_type = value
      else:
        self.send(event, value)
    else:
      self.send(event, value)

template unwrap(self: PreprocessingHandler, event: ParseEvent) =
  unwrap(self, event, event.value)

template unwrap(self: PreprocessingHandler, value: Value) =
  unwrap(self, nil, value)

proc handle(h: ParseHandler, event: ParseEvent) =
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
    self.unwrap(event)
  of PeToken:
    if event.token[0] == '^':
      let parsed = parse_key(event.token)
      let last = self.stack[^1]
      if last.defer:
        if parsed.keys.len > 1:
          todo()
        else:
          if parsed.value.is_nil:
            last.state = PhMapValue
            last.key = parsed.keys[0]
          else:
            last.state = PhMapKey
            last.value.map[parsed.keys[0]] = parsed.value
      else:
        self.next.do_handle(ParseEvent(kind: PeKey, key: parsed.keys[0]))
        if parsed.keys.len > 1:
          for key in parsed.keys[1..^1]:
            self.next.do_handle(ParseEvent(kind: PeMapShortcut, key: key))
        if not parsed.value.is_nil:
          self.next.do_handle(ParseEvent(kind: PeValue, value: parsed.value))
    else:
      let value = interpret_token(event.token)
      unwrap(self, value)
  of PeStartVector:
    var context = PrepHandlerContext(state: PhVectorStart)
    self.stack.add(context)
    self.next.do_handle(event)
  of PeEndVectorOrSet:
    let context = self.stack.pop()
    if context.defer:
      unwrap(self, context.value)
    else:
      self.next.do_handle(event)
  of PeStartMap:
    let `defer` = (self.stack.len > 0 and self.stack[^1].defer)
    var context = PrepHandlerContext(state: PhMapStart, `defer`: `defer`)
    self.stack.add(context)
    if `defer`:
      context.value = new_gene_map()
    else:
      self.next.do_handle(event)
  of PeEndMap:
    let context = self.stack.pop()
    if context.state == PhStrValueStart:
      self.stack[^1].value.gene_children.add(context.value)
      self.parser.state = PsStrInterpolation
    elif context.defer:
      unwrap(self, context.value)
    else:
      self.next.do_handle(event)
  of PeStartGene:
    var context = PrepHandlerContext(state: PhGeneStart)
    self.stack.add(context)
    self.next.do_handle(event)
  of PeEndGene:
    let context = self.stack.pop()
    if context.defer:
      let last = self.stack[^1]
      case last.state:
      of PhStrInterpolation:
        last.value.gene_children.add(context.value)
        self.parser.state = PsStrInterpolation
      else:
        unwrap(self, context.value)
    else:
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
    self.parser.state = PsStrInterpolation
  of PeStartStrValue:
    var context = PrepHandlerContext(
      state: PhStrValueStart,
      `defer`: true,
    )
    self.stack.add(context)
    self.parser.state = PsDefault
  of PeStartStrGene:
    var context = PrepHandlerContext(
      state: PhGeneStart,
      value: new_gene_gene(),
      `defer`: true,
    )
    self.stack.add(context)
    self.parser.state = PsDefault
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

proc new_preprocessing_handler*(parser: ptr Parser): PreprocessingHandler =
  PreprocessingHandler(
    parser: parser,
    handle: handle,
  )

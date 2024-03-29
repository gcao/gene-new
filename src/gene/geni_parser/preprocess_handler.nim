import tables, sets

import ../types
import ./base

type
  PrepHandlerState* = enum
    PhDefault

    PhRoot

    PhLine
    PhLineItem

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

    PhVector

    PhSet

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

    PhQuote           # :
    PhUnquote         # %

    PhDecoratorStart  # #@
    PhDecoratorFirst

  PrepHandlerContext* = ref object
    # case state*: PrepHandlerState
    # of PhLine:
    #   items*: seq[PrepHandlerContext]
    # else:
    #   key*: string
    #   value*: Value
    state*: PrepHandlerState
    gene_type_symbol*: string # The string value of the gene type if it is a symbol.
    key*: string
    indent*: int
    # `defer`*: bool  # Whether to defer forwarding the event to the next handler.

  # We would like to share as little as possible between the PreprocessingHandler and the ValueHandler.
  # However, we would like to achieve the best performance possible. So we need to minimize the number
  # of allocations and copies etc.

  # Handle basic parsing and pre-processing (e.g. ???), raise errors if the input is not valid Gene data.
  PreprocessingHandler* = ref object of ParseHandler
    continue_map*: Table[string, HashSet[string]]
    stack*: seq[PrepHandlerContext]

proc get_indent(self: PreprocessingHandler): int =
  if self.stack.len == 0:
    return 0
  else:
    return self.stack[^1].indent

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

proc is_continue(self: PreprocessingHandler, key: string, value: Value): bool =
  if value.kind == VkSymbol and self.continue_map.has_key(key):
    return self.continue_map[key].contains(value.str)

proc unwrap(self: PreprocessingHandler, event: ParseEvent, value: Value) =
  if self.stack.len == 0:
    self.send(event, value)
  else:
    var last = self.stack[^1]
    case last.state:
    of PhMapKey:
      last.state = PhMapValue
      # if last.defer:
      #   last.value.map[last.key] = value
      # else:
      #   self.send(event, value)
      self.send(event, value)
    # of PhStrInterpolation:
    #   last.value.gene_children.add(value)
    #   self.parser.state = PsStrInterpolation
    # of PhStrValueStart:
    #   if last.value.is_nil:
    #     last.value = value
    #   else:
    #     not_allowed()
    of PhGeneStart:
      last.state = PhGeneType
      # if last.defer:
      #   last.value.gene_type = value
      # else:
      #   self.send(event, value)
      self.send(event, value)
    of PhLine:
      if self.stack.len > 1 and self.is_continue(self.stack[^2].gene_type_symbol, value):
        if event.is_nil:
          self.next.do_handle(ParseEvent(kind: PeValue, value: value))
        else:
          self.next.do_handle(event)
      else:
        var context = PrepHandlerContext(
          state: PhGeneType,
          indent: last.indent,
        )
        if value.kind == VkSymbol:
          context.gene_type_symbol = value.str
        self.stack.add(context)
        self.next.do_handle(ParseEvent(kind: PeStartGene))
        if event.is_nil:
          self.next.do_handle(ParseEvent(kind: PeValue, value: value))
        else:
          self.next.do_handle(event)
        # var context = PrepHandlerContext(state: PhLineItem, value: value)
        # last.items.add(context)
    else:
      self.send(event, value)

template unwrap(self: PreprocessingHandler, event: ParseEvent) =
  unwrap(self, event, event.value)

template unwrap(self: PreprocessingHandler, value: Value) =
  unwrap(self, nil, value)

# proc process_end(self: PreprocessingHandler) =
#   while self.stack.len > 0:
#     var context = self.stack.pop()
#     case context.state:
#     of PhLine:
#       if context.items.len > 0:
#         var first = context.items[0]
#         if first.value.kind == VkSymbol and first.value.str == "=":
#           for item in context.items[1..^1]:
#             self.unwrap(item.value)
#             # self.next.do_handle(ParseEvent(kind: PeValue, value: item.value))
#         else:
#           var value = new_gene_gene(first.value)
#           for item in context.items[1..^1]:
#             value.gene_children.add(item.value)
#           self.unwrap(value)
#     else:
#       todo($context.state)

# proc process_indentation(self: PreprocessingHandler) =
#   if self.stack.len == 0:
#     return
#   var c0 = self.stack[^1]
#   if c0.state != PhLine:
#     return
#   if self.stack.len < 2:
#     return
#   var c1 = self.stack[^2]
#   if c1.state != PhLine:
#     return
#   if c0.indent > c1.indent:
#     return

#   let first = c1.items[0]
#   if first.value.kind == VkSymbol and first.value.str == "=":
#     for item in c1.items[1..^1]:
#       self.next.do_handle(ParseEvent(kind: PeValue, value: item.value))
#   else:
#     var value = new_gene_gene()
#     value.gene_type = first.value
#     for item in c1.items[1..^1]:
#       value.gene_children.add(item.value)
#     self.next.do_handle(ParseEvent(kind: PeValue, value: value))

proc handle(h: ParseHandler, event: ParseEvent) =
  var self = cast[PreprocessingHandler](h)
  # echo "PreprocessingHandler " & $event
  case event.kind:
  of PeStart:
    self.stack.add(PrepHandlerContext(state: PhRoot))
    self.next.do_handle(event)
    # if self.parser.mode == PmDocument:
    #   var context = PrepHandlerContext(state: PhDocStart)
    #   self.stack.add(context)
    #   self.next.do_handle(event)
    #   self.next.do_handle(ParseEvent(kind: PeStartDocument))
  of PeEnd:
    # self.process_end()
    self.next.do_handle(event)
  of PeNewLine:
    if self.stack.len > 0:
      var last = self.stack[^1]
      if last.state == PhLine:
        discard self.stack.pop()
        # if last.items.len == 0:
        #   discard self.stack.pop()
        # else:
        #   not_allowed()
    # self.process_indentation()
    var context = PrepHandlerContext(state: PhLine)
    self.stack.add(context)
  of PeIndent:
    let context = self.stack[^1]
    context.indent = event.indent
  of PeValue:
    self.unwrap(event)
  of PeToken:
    if event.token == "=":
      let last = self.stack[^1]
      if last.state == PhLine:
        discard self.stack.pop()
      else:
        self.unwrap(nil, new_gene_symbol("="))
    elif event.token[0] == '^':
      let parsed = parse_key(event.token)
      # let last = self.stack[^1]
      # if last.defer:
      #   if parsed.keys.len > 1:
      #     todo()
      #   else:
      #     if parsed.value.is_nil:
      #       last.state = PhMapValue
      #       last.key = parsed.keys[0]
      #     else:
      #       last.state = PhMapKey
      #       last.value.map[parsed.keys[0]] = parsed.value
      # else:
      #   self.next.do_handle(ParseEvent(kind: PeKey, key: parsed.keys[0]))
      #   if parsed.keys.len > 1:
      #     for key in parsed.keys[1..^1]:
      #       self.next.do_handle(ParseEvent(kind: PeMapShortcut, key: key))
      #   if not parsed.value.is_nil:
      #     self.next.do_handle(ParseEvent(kind: PeValue, value: parsed.value))
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
    var context = PrepHandlerContext(state: PhVector, indent: self.get_indent())
    self.stack.add(context)
    self.next.do_handle(event)
  of PeEndVectorOrSet:
    # let context = self.stack.pop()
    # if context.defer:
    #   unwrap(self, context.value)
    # else:
    #   self.next.do_handle(event)
    self.next.do_handle(event)
  of PeStartMap:
    # let `defer` = (self.stack.len > 0 and self.stack[^1].defer)
    # var context = PrepHandlerContext(state: PhMapStart, `defer`: `defer`, indent: self.get_indent())
    # self.stack.add(context)
    # if `defer`:
    #   context.value = new_gene_map()
    # else:
    #   self.next.do_handle(event)
    self.next.do_handle(event)
  of PeEndMap:
    # let context = self.stack.pop()
    # if context.state == PhStrValueStart:
    #   self.stack[^1].value.gene_children.add(context.value)
    #   self.parser.state = PsStrInterpolation
    # elif context.defer:
    #   unwrap(self, context.value)
    # else:
    #   self.next.do_handle(event)
    self.next.do_handle(event)
  of PeStartGene:
    var context = PrepHandlerContext(state: PhGeneStart, indent: self.get_indent())
    self.stack.add(context)
    self.next.do_handle(event)
  of PeEndGene:
    # let context = self.stack.pop()
    # if context.defer:
    #   let last = self.stack[^1]
    #   case last.state:
    #   of PhStrInterpolation:
    #     last.value.gene_children.add(context.value)
    #     self.parser.state = PsStrInterpolation
    #   else:
    #     unwrap(self, context.value)
    # else:
    #   self.next.do_handle(event)
    self.next.do_handle(event)
  of PeStartSet:
    var context = PrepHandlerContext(state: PhSet, indent: self.get_indent())
    self.stack.add(context)
    self.next.do_handle(event)
  of PeQuote, PeUnquote:
    self.next.do_handle(event)
  of PeStartDecorator:
    self.next.do_handle(event)
  # of PeStartStrInterpolation:
  #   var context = PrepHandlerContext(
  #     state: PhStrInterpolation,
  #     value: new_gene_gene(new_gene_symbol("#Str")),
  #     indent: self.get_indent(),
  #   )
  #   self.stack.add(context)
  #   self.parser.state = PsStrInterpolation
  # of PeStartStrValue:
  #   var context = PrepHandlerContext(
  #     state: PhStrValueStart,
  #     `defer`: true,
  #     indent: self.get_indent(),
  #   )
  #   self.stack.add(context)
  #   self.parser.state = PsDefault
  # of PeStartStrGene:
  #   var context = PrepHandlerContext(
  #     state: PhGeneStart,
  #     value: new_gene_gene(),
  #     `defer`: true,
  #     indent: self.get_indent(),
  #   )
  #   self.stack.add(context)
  #   self.parser.state = PsDefault
  # of PeEndStrInterpolation:
  #   let last = self.stack.pop()
  #   var all_are_string = true
  #   for child in last.value.gene_children:
  #     if child.kind != VkString:
  #       all_are_string = false
  #       break
  #   if all_are_string:
  #     let value = new_gene_string("")
  #     for child in last.value.gene_children:
  #       value.str.add(child.str)
  #     self.next.do_handle(ParseEvent(kind: PeValue, value: value))
  #   else:
  #     self.next.do_handle(ParseEvent(kind: PeValue, value: last.value))
  else:
    todo($event)

proc new_preprocessing_handler*(parser: ptr Parser): PreprocessingHandler =
  PreprocessingHandler(
    parser: parser,
    handle: handle,
  )

proc new_preprocessing_handler*(parser: ptr Parser, continue_map: Table[string, HashSet[string]]): PreprocessingHandler =
  PreprocessingHandler(
    parser: parser,
    handle: handle,
    continue_map: continue_map,
  )

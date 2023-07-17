import tables, sets

import ../types
import ./base

type
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
  echo "handle_value " & $self.stack.len & " " & $event
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

proc new_value_handler*(parser: ptr Parser): ValueHandler =
  ValueHandler(
    parser: parser,
    handle: handle_value,
  )

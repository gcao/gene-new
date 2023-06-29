import streams

import ./types
import ./parser/base
import ./parser/geni_handler
import ./parser/value_handler

export ParseError

proc new_parser*(options: ParseOptions): Parser =
  if not INITIALIZED:
    init()

  result = Parser(
    format: IfGeni,
    options: new_options(options),
    references: References(),
  )
  result.handler = new_geni_handler(result.addr)

proc new_parser*(): Parser =
  if not INITIALIZED:
    init()

  result = Parser(
    format: IfGeni,
    options: default_options(),
    references: References(),
  )
  result.handler = new_geni_handler(result.addr)

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

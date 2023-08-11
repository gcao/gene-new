import tables, sets, streams

import ./types
import ./geni_parser/base
import ./geni_parser/preprocess_handler
import ./geni_parser/value_handler

export ParseError

proc create_continue_map(): Table[string, HashSet[string]] =
  result = {
    "if": to_hash_set(["elif", "else"]),
  }.to_table()

proc new_parser*(options: ParseOptions): Parser =
  if not INITIALIZED:
    init()

  result = Parser(
    options: new_options(options),
    references: References(),
  )
  result.handler = new_preprocessing_handler(result.addr, create_continue_map())

proc new_parser*(): Parser =
  if not INITIALIZED:
    init()

  result = Parser(
    options: default_options(),
    references: References(),
  )
  result.handler = new_preprocessing_handler(result.addr, create_continue_map())

proc read_first*(self: var Parser): Value =
  let value_handler = new_value_handler(self.addr)
  self.handler.next = value_handler
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

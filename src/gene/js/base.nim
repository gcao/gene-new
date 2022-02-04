import ../types

type
  Translator* = ref object

proc new_translator*(): Translator =
  Translator()

proc process*(self: Translator, data: Value): string =
  todo("translate2js " & $data)

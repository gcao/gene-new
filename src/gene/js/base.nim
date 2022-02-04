import ../types

# Performance is not as critical as the interpreter because this is usually run only once.

# Use a pipeline to handle the translation
# Like middlewares and request handlers used in web applications

type
  Translator* = ref object

proc new_translator*(): Translator =
  Translator()

proc process*(self: Translator, data: Value): string =
  case data.kind
  of VkNil:
    result = "nil"
  else:
    todo("translator.process " & $data)

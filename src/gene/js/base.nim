import ../types

# Performance is not as critical as the interpreter because this is usually run only once.

# Use a pipeline to handle the translation
# Like middlewares and request handlers used in web applications

# https://lisperator.net/pltut/compiler/js-codegen
# https://tomassetti.me/code-generation/

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

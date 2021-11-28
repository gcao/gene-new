include gene/extension/boilerplate
import gene/utils

{.push dynlib exportc.}

proc init*(): Value {.wrap_exception.} =
  result = new_namespace("sqlite")
  GENEX_NS.ns["sqlite"] = result

{.pop.}

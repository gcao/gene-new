import ../gene/types
import ../gene/interpreter_base

# CSS

# * Translate sass to css

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    discard self.eval(self.runtime.pkg, """
      (ns genex/css
        (fn sass str
          (todo "sass")
        )
      )
    """)

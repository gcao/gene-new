import ../types

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    discard

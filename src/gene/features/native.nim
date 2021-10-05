import ../types

proc test(self: Value, args: Value): Value {.nimcall.} =
  1

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    GENE_NATIVE_NS.ns["_test_"] = new_gene_native_method(test)

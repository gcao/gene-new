# import unittest

# import gene/types

# import ./helpers

# test "GeneAny":
#   var s = "abc"
#   var g = GeneValue(
#     kind: GeneAny,
#     any: cast[pointer](s.addr),
#   )
#   check cast[ptr string](g.any)[] == s

# test_core "gene", proc(r: GeneValue) =
#   check r.internal.ns.name == "gene"

# test_core "genex", proc(r: GeneValue) =
#   check r.internal.ns.name == "genex"

# test_core "(assert true)", GeneNil

# test_core "(AssertionError .name)", "AssertionError"

# # test_core """
# #   $runtime
# # """, proc(r: GeneValue) =
# #   check r.internal.runtime.home == "/Users/gcao/proj/gene.nim"
# #   check r.internal.runtime.version == "0.1.0"

import unittest

import gene/types

test "GeneAny":
  var s = "abc"
  var g = GeneValue(
    kind: GeneAny,
    any: cast[pointer](s.addr),
  )
  check cast[ptr string](g.any)[] == s

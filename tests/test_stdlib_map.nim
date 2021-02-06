import gene/types

import ./helpers

test_core """
  ({^a 1 ^b 2} .size)
""", 2

test_core """
  ({^a 1 ^b 2} .keys)
""", @[new_gene_string("a"), new_gene_string("b")]

test_core """
  ({^a 1 ^b 2} .values)
""", @[new_gene_int(1), new_gene_int(2)]

test_core """
  (var sum 0)
  ({^a 1 ^b 2} .each
    ([_ v] -> (sum += v))
  )
  sum
""", 3

test_core """
  ({^a 1 ^b 2} .map
    ([_ v] -> v)
  )
""", @[new_gene_int(1), new_gene_int(2)]

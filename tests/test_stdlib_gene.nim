import gene/types

import ./helpers

test_core """
  (:(1 ^a 2 3 4) .type)
""", 1

test_core """
  (:(1 ^a 2 3 4) .data)
""", @[new_gene_int(3), new_gene_int(4)]

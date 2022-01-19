import tables

import gene/types

import ./helpers

test_interpreter """
  (:(1 ^a 2 3 4) .type)
""", 1

test_interpreter """
  (:(1 ^a 2 3 4) .props)
""", {"a": new_gene_int(2)}.toOrderedTable

test_interpreter """
  (:(1 ^a 2 3 4) .children)
""", @[3, 4]

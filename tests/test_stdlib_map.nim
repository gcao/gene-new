import gene/types

import ./helpers

test_interpreter """
  ({^a 1 ^b 2} .size)
""", 2

# test_interpreter """
#   ({^a 1 ^b 2} .keys)
# """, @[new_gene_string("a"), new_gene_string("b")]

# test_interpreter """
#   ({^a 1 ^b 2} .values)
# """, @[1, 2]

# test_interpreter """
#   (var sum 0)
#   ({^a 1 ^b 2} .each
#     ([_ v] -> (sum += v))
#   )
#   sum
# """, 3

# test_interpreter """
#   ({^a 1 ^b 2} .map
#     ([_ v] -> v)
#   )
# """, @[1, 2]

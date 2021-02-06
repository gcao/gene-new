# import unittest

# import gene/types
# import gene/interpreter

# import ./helpers

# test_core """
#   (var sum 0)
#   (for v in (gene/native/props_iterator {^a 1 ^b 2})
#     (sum += v)
#   )
#   sum
# """, 3

# test_core """
#   (var sum 0)
#   (for v in ({^a 1 ^b 2}.to_iterator)
#     (sum += v)
#   )
#   sum
# """, 3

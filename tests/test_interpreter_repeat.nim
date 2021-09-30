import gene/types

import ./helpers

test_interpreter """
  (var sum 0)
  (repeat 3
    (sum = (sum + 1))
  )
  sum
""", 3

# test_interpreter """
#   (var sum 0)
#   (repeat 4 ^index i
#     (sum += i)
#   )
#   sum
# """, 6 # 0, 1, 2, 3

# test_interpreter """
#   (var sum 0)
#   (repeat 3 ^total total
#     (sum += total)
#   )
#   sum
# """, 9

# test_interpreter """
#   (var sum 0)
#   (repeat 3
#     # "$once" make sure the statement is executed at most once in a loop.
#     ($once (sum += 1))
#   )
#   sum
# """, 1

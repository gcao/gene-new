import gene/types

import ./helpers

# test_interpreter """
#   (var sum 0)
#   (for i in (range 0 4)
#     (sum += i)
#   )
#   sum
# """, 6 # 0 + 1 + 2 + 3

# test_interpreter """
#   (var sum 0)
#   (for i in (range 0 4)
#     (sum += i)
#     (if (i < 2)
#       (continue)
#     else
#       (break)
#     )
#     (sum = 10000)  # should not reach here
#   )
#   sum
# """, 3 # 0 + 1 + 2

test_interpreter """
  (var sum 0)
  (for i in [1 2 3]
    (sum += i)
  )
  sum
""", 6

test_interpreter """
  (var sum 0)
  (for v in {^a 1 ^b 2}
    (sum += v)
  )
  sum
""", 3

test_interpreter """
  (var sum 0)
  (for [k v] in {^a 1 ^b 2}
    (sum += v)
  )
  sum
""", 3

test_interpreter """
  (var sum 0)
  (for [i _] in [1 2 3]
    (sum += i)
  )
  sum
""", 3

test_interpreter """
  [(for i in [1 2]
    ($emit i)
  )]
""", @[1, 2]

test_interpreter """
  [(for i in [1 2]
    ($emit i i)
  )]
""", @[1, 1, 2, 2]

test_interpreter """
  [(for i in [1 2]
    ($once ($emit i)) # $emit will be executed only once
  )]
""", @[1]

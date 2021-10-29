import gene/types

import ./helpers

test_interpreter "(1 + 2)", 3
test_interpreter "(1 - 2)", -1

test_interpreter """
  (1 + 2 + 3)
""", 6

test_interpreter """
  (2 * 3 + 4)
""", 10

test_interpreter """
  (2 + 3 * 4)
""", 14

# test_interpreter """
#   (2 + 3 * 4 ** 2) # (4*4) * 3 + 2
# """, 50

test_interpreter """
  (var a 3)
  (2 < a < 4)
""", true

test_interpreter """
  (var a 5)
  (2 < a < 4)
""", false

test_interpreter """
  (true && false || true)
""", true

test_interpreter """
  (false || false && true || true)  # && > ||
""", true

test_interpreter """
  (1 || 2)
""", 1

test_interpreter """
  (true && 2)
""", 2

test_interpreter """
  (var a)
  (a = 2)
""", 2

# Make it work like this?
# (a = b) => (a = b)
# (a = b = 2) => (a = (b = 2))
# (a = b + 2) => (a = (b + 2))
# (a += b = 2) => (a += (b = 2)) = (a = (a + (b = 2)))
# test_interpreter """
#   (var a)
#   (var b)
#   (a = b = 2)
#   (a + b)
# """, 4

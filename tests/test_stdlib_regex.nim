import gene/types

import ./helpers

# test_interpreter """
#   ((#/a/ .class).name)
# """, "Pattern"

test_interpreter """
  (!!("a" =~ #/a/))
""", True

test_interpreter """
  ("a" =~ #/(a)/)
  $~0
""", "a"

test_interpreter """
  ("a" !~ #/a/)
""", False

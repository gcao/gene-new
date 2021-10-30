import gene/types

import ./helpers

# test_interpreter """
#   ((#/a/ .class).name)
# """, "Pattern"

test_interpreter """
  (!!("a" =~ #/a/))
""", true

test_interpreter """
  ("a" !~ #/a/)
""", false

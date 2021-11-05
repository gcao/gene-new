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

test_interpreter """
  ("ab" =~ ($regex "(a" "b)"))
  $~0
""", "ab"

test_interpreter """
  ("AB" =~ ($regex ^^i "(a" "b)"))
  $~0
""", "AB"

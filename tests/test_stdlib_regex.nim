import gene/types

import ./helpers

# test_interpreter """
#   ((#/a/ .class).name)
# """, "Pattern"

test_interpreter """
  (!!("a" =~ #/a/))
""", Value(kind: VkBool, bool: true)

test_interpreter """
  ("a" =~ #/(a)/)
  $~0
""", "a"

test_interpreter """
  ("a" !~ #/a/)
""", Value(kind: VkBool, bool: false)

test_interpreter """
  ("ab" =~ ($regex "(a" "b)"))
  $~0
""", "ab"

test_interpreter """
  ("AB" =~ ($regex ^^i "(a" "b)"))
  $~0
""", "AB"

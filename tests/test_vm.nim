import gene/types

import ./helpers

test_vm """
  1
""", 1

test_vm """
  (1 + 2)
""", 3

# (do ...) will create a scope if needed, execute all statements and return the result of the last statement.
# `catch` and `ensure` can be used inside `do`.
# `ensure` will run after `catch` if both are present? but the exception thrown in `ensure` will be ignored?

test_vm """
  (do 1 2 3)
""", 3

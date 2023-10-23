import tables

import gene/types

import ./helpers

test_vm "nil", Value(kind: VkNil)
test_vm "1", 1
test_vm "true", true
test_vm "false", false
test_vm "\"string\"", "string"

test_vm "[1 2]", new_gene_vec(1, 2)

test_vm "{^a 1}", {"a": new_gene_int(1)}.toTable

# test_vm "1 2 3", 3

test_vm "(1 + 2)", 3

test_vm "(1 < 2)", true

# (do ...) will create a scope if needed, execute all statements and return the result of the last statement.
# `catch` and `ensure` can be used inside `do`.
# `ensure` will run after `catch` if both are present? but the exception thrown in `ensure` will be ignored?

test_vm """
  (do 1 2 3)
""", 3

test_vm """
  (if true
    1
  else
    2
  )
""", 1

test_vm """
  (if false
    1
  else
    2
  )
""", 2

test_vm """
  (var i 1)
  i
""", 1

test_vm """
  (var i 1)
  (i + 2)
""", 3

test_vm """
  (do
    (var i 1)
    i
  )
""", 1

test_vm """
  (loop
    1
    (break)
  )
  2
""", 2

test_vm """
  (loop
    (break 1)
  )
""", 1

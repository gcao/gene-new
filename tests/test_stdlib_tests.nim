import ./helpers

test_interpreter """
  (genex/test/check (1 == 1))
"""

test_interpreter """
  (import genex/test/[check fail TestFailure])
  (try
    (check (1 == 1))
    (fail)
  catch TestFailure
  )
"""

# test_interpreter """
#   (import genex/test/[check fail TestFailure])
#   (try
#     (check (1 == 1) "error message")
#     (fail)
#   catch TestFailure
#     (check ($ex/.message == "error message"))
#   )
# """

# test_interpreter """
# (import genex/test/[suite test skip_test])

# (suite "A suite"
#   (test "A basic test"
#     (assert true)
#   )

#   (test "A failing test"
#     (assert false)
#   )

#   (skip_test "A failing test"
#     (assert false)
#   )

#   (skip_test "Another failing test"
#     (fail)
#   )
# )
# """

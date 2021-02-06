import ./helpers

test_core """

(import genex/tests/[suite test skip_test])

(suite "A suite"
  (test "A basic test"
    (assert true)
  )

  (test "A failing test"
    (assert false)
  )

  (skip_test "A failing test"
    (assert false)
  )

  (skip_test "Another failing test"
    (fail)
  )
)

"""

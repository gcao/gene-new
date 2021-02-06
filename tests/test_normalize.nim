import ./helpers

test_normalize "(1 + 2)", "(+ 1 2)"

test_normalize "(.@test)",
  "((@ \"test\") self)"

test_normalize "(.@ \"test\")",
  "((@ \"test\") self)"

test_normalize "(something .@test)",
  "((@ \"test\") something)"

test_normalize "(something .@ \"test\")",
  "((@ \"test\") something)"

test_normalize "(@test = 1)",
  "($set self @test 1)"

# (if ...)
test_normalize """
  (if a b else c)
""", """
  (if
    ^cond a
    ^then [b]
    ^else [c]
  )
"""

test_normalize """
  (if not a b)
""", """
  (if
    ^cond (not a)
    ^then [b]
    ^else []
  )
"""

import gene/types

import ./helpers

# (defined? a)
# (defined_in_scope? a)
# (scope)
# (scope ^!inherit)

test_interpreter """
  (var i 0)
  (fn f _
    i
  )
  (var i 1)
  (f)
""", 0

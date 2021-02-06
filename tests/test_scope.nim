import gene/types

import ./helpers

test_interpreter """
  (var i 0)
  (fn f _
    i
  )
  (var i 1)
  (f)
""", 0

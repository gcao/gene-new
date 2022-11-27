import gene/types

import ./helpers

test_interpreter """
  (spawn
    (1 + 2)
  )
""", 3

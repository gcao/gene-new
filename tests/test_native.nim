import gene/types

import ./helpers

# Native functions / methods

test_interpreter """
  # gene/native/test is defined in tests/helpers.nim:init_all()
  (gene/native/test)
""", 1

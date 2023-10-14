import gene/types

import ./helpers

test_vm """
  1
""", 1

test_vm """
  (1 + 2)
""", 3

import gene/types

import ./helpers

# Cast an object of one type to another, with optional behavior overwriting
# Typical use: (cast (new A) B ...)

test_interpreter """
  (class A
    (method test _
      1
    )
  )
  (class B
    (method test _
      2
    )
  )
  ((cast (new A) B).test)
""", 2

import unittest, tables

import gene/types

import ./helpers

test_vm """
  (fn f []
  )
""", proc(r: Value) =
  check r.fn.name == "f"

test_vm """
  (fn f []
    1
  )
  (f)
""", 1

test_vm """
  (fn f [a]
    (a + 2)
  )
  (f 1)
""", 3

test_vm """
  (fn f a
    (a + 2)
  )
  (f 1)
""", 3

test_vm """
  (fn f [a b]
    (a + b)
  )
  (f 1 2)
""", 3

test_vm """
  (fn f []
    (return 1)
    2
  )
  (f)
""", 1

test_vm """
  (fn f []
    (g)
  )
  (fn g []
    1
  )
  (f)
""", 1

test_vm """
  (var a 1)
  (fn f b
    (a + b)
  )
  (f 2)
""", 3

test_vm """
  (var a 1)
  (fn f []
    (var b 2)
    (fn g []
      (a + b)
    )
  )
  ((f))
""", 3

test_vm """
  ((fnx _
    1
  ))
""", 1

test_vm """
  (var a (fnx _
    1
  ))
  (a)
""", 1

# TODO
# test_vm """
#   # Creates a named function but does not add it to the namespace automatically
#   (fn "f" []
#   )
# """, proc(r: Value) =
#   check r.fn.name == "f"

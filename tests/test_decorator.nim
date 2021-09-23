import gene/types

import ./helpers

# Decorator
#
# * Can be applied to array item, Gene data item
# * It's applied when expressions are created
# * Simple decorator: +pub x        -> (call ^^decorator pub [x])
# * Complex decorator: (+add 2) x   -> (call ^^decorator (add 2) [x])
# * Support +dec x...               -> (explode (call ^^decorator dec [x]))
#

test_interpreter """
  (fn f target
    ("" target "y")
  )
  [+f "x"]
""", @[new_gene_string("xy")]

test_interpreter """
  (fn f target
    ("" target "y")
  )
  [+f +f "x"]
""", @[new_gene_string("xyy")]

test_interpreter """
  (fn f target
    ("" target "y")
  )
  (fn g a
    a
  )
  (g +f "x")
""", "xy"

test_interpreter """
  (fn f a
    (fnx target
      ("" a target)
    )
  )
  [(+f "x") "y"]
""", @[new_gene_string("xy")]

test_interpreter """
  (fn f target
    ("" target "y")
  )
  +f "x"
""", new_gene_string("xy")

# test_interpreter """
#   (ns n
#     (fn f target
#       ("" target "y")
#     )
#   )
#   +n/f "x"
# """, new_gene_string("xy")

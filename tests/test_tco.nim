import gene/types

import ./helpers

# Add is_last*: bool to Expr
# When invoke function, set its last expression's is_last to true
# When eval an expression, if it's last, pass is_last to its last child expresson.
#   This applies to some expressions only, e.g. function body, `if`, `do` etc
# When a function call is detected as a tail call, it'll throw a special exception
#   which is caught by the caller of the original function, and the caller will
#   invoke the nested function.

# test_interpreter """
#   (fn f [sum n]
#     (if (n == 0)
#       sum
#     else
#       (f (sum + n) (n - 1))
#     )
#   )
#   (f 0 1000)
# """, 500500

import gene/types
import gene/interpreter_base

import ../helpers

# Test JavaScript code generation
# Test Execution of generated JS code - use Node.js, check output

test_jsgen """
  (println 1)
""", "1"

# test_jsgen """
#   (fn f [] 1)
#   (println (f))
# """, "1"

import gene/types
import gene/interpreter_base

import ../helpers

# Test JavaScript code generation
# Test Execution of generated JS code - use Node.js, check output

# Use uglifyjs or something else to reformat JS output for better debugging purpose
# Use environment variable to control output of raw and beautified js output

# test_jsgen """
#   (import gene/js/*)
#   (js
#     (println* [1 2])
#   )
# """, "[1, 2]\n"

test_jsgen """
  (import gene/js/*)
  (js
    (var* a 1)
    (println* :a)
  )
""", "1\n"

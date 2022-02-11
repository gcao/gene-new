import gene/types
import gene/interpreter_base

import ../helpers

# Test JavaScript code generation
# Test Execution of generated JS code - use Node.js, check output

# Use uglifyjs or something else to reformat JS output for better debugging purpose
# Use environment variable to control output of raw and beautified js output

test_jsgen """
  (import genex/js/*)
  (js
    (console/log "abc")
  )
""", "abc\n"

test_jsgen """
  (import genex/js/*)
  (js
    (console/log [1 2])
  )
""", "[ 1, 2 ]\n" # the extra spaces after "[" are special behavior of node.js

test_jsgen """
  (import genex/js/*)
  (js
    (console/log {^a 1 ^b 2})
  )
""", "{ a: 1, b: 2 }\n" # the extra spaces after "{" are special behavior of node.js

test_jsgen """
  (import genex/js/*)
  (js
    (var a 1)
    (console/log a)
  )
""", "1\n"

test_jsgen """
  (import genex/js/*)
  (js
    (if true
      (console/log 1)
    else
      (console/log 2)
    )
  )
""", "1\n"

test_jsgen """
  (import genex/js/*)
  (js
    (console/log (? true 1 2))
  )
""", "1\n"

test_jsgen """
  (import genex/js/*)
  (js
    (console/log (? false 1 2))
  )
""", "2\n"

test_jsgen """
  (import genex/js/*)
  (js
    (fn* f a
      (return (a + 1))
    )
    (console/log (f 1))
  )
""", "2\n"

test_jsgen """
  (import genex/js/*)
  (js
    (var f (fnx* a
      (return (a + 1))
    ))
    (console/log (f 1))
  )
""", "2\n"

test_jsgen """
  (import genex/js/*)
  (js
    (var a [1 2])
    (console/log a/0) # -> a[0]
  )
""", "1\n"

test_jsgen """
  (import genex/js/*)
  (js
    (var a [1 2])
    (console/log (a @0)) # -> a[0]
  )
""", "1\n"

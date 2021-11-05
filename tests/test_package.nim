import unittest

import gene/types
import gene/interpreter

import ./helpers

# How packaging work

test_interpreter """
  $pkg/.name
""", "gene"

# test_interpreter """
#   ($dep "my-lib" "*" ^location "local:example-projects/my-lib")
#   (import x from "index" of "my-lib")
#   (x)
# """, 1

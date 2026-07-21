import unittest, tables

import gene/types

import ./helpers

# Do not introduce too much complexity!!!

# Unify function argument parsing and pattern matching.

# Mode:
#   Function/macro argument parsing
#   Block argument parsing - more relax than function argument parsing ?!
#   Variable definition
#   Assignment
# Nesting - support nested Array, Map and Gene
# Match type, props and children
# Aliasing: type/props mapped to different names in scope or namespace
# Splatting: [a ... b], [a... b], [a b...]
# Place holder symbol: [a ... :b ... c]
# Rest of properties: ^rest...
# Required, optional
# Default value
# Type checking
# Error handling (different mode may have different error handling behavior)
#   Extra values provided
#   Required values missing
#   Type mismatch
# Efficient

# Use [] to encapsulate a pattern

# (fn f a ...)  = (fn f [a] ...)
# (a => ...)    = ([a] => ...)

# var creates a new variable with same name if a variable is already defined.
# (var a x)    != (var [a] x)
# (var [^a ^!b ^c = 3] ())   => a is missing, b = nil, c = 3   => error

# (a = x)      != ([a] = x)

test_vm """
  (fn f a
    a
  )
  (f 1)
""", 1

test_vm """
  (fn f [a]
    a
  )
  (f 1)
""", 1

test_vm """
  (fn f [a b]
    (a + b)
  )
  (f 1 2)
""", 3

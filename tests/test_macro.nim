# import unittest

import gene/types

import ./helpers

# Macro support
#
# * A macro will generate an AST tree and pass back to the VM to execute.
#

test_interpreter """
  (macro m [a b]
    (a + b)
  )
  (m 1 2)
""", 3

test_interpreter """
  (macro m b
    b
  )
  (m a)
""", new_gene_symbol("a")

test_interpreter """
  (var a 1)
  (macro m []
    (caller_eval :a)
  )
  (m)
""", 1

test_interpreter """
  (var a 1)
  (macro m b
    (caller_eval b)
  )
  (m a)
""", 1

test_core """
  (macro m _
    (class A
      (method test _ "A.test")
    )
    (caller_eval
      (:$def_ns_member "B" A)
    )
  )
  (m)
  ((new B) .test)
""", "A.test"

test_core """
  (macro m name
    (class A
      (method test _ "A.test")
    )
    (caller_eval
      (:$def_ns_member name A)
    )
  )
  (m "B")
  ((new B) .test)
""", "A.test"

# TODO: this should be possible with macro/caller_eval etc
test_interpreter """
  (macro with [name value body...]
    (var expr
      :(do
        (var %name %value)
        %body...
        %name))
    (caller_eval expr)
  )
  (var b "b")
  (with a "a"
    (a = (a b))
  )
""", "ab"

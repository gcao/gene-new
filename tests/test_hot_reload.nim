import unittest

import gene/types
import gene/interpreter

import ./helpers

# HOT RELOAD

# Module must be marked as reloadable first
# We need symbol table per module
# Symbols are referenced by names/keys
# Should work for imported symbols, e.g. (import a from "a")
# Should work for aliases when a symbol is imported, e.g. (import a as b from "a")
# Should not reload `b` if `b` is defined like (import a from "a") (var b a)
# Should work for child members of imported symbols, e.g. (import a from "a") a/b
# Should work with the entry module (i.e. the script that is invoked)
# Should use the reloaded version when a symbol is accessed

# Reload occurs in the same thread at controllable interval.
# https://github.com/paul-nameless/nim-fswatch
# https://github.com/FedericoCeratto/nim-fswatch

# Test design

# Load a module
# Run code and validate output
# Update the module's content
# Wait a moment
# Run code and validate output is new
# Make sure module is reverted to old content

# test_interpreter """
#   (var mod "tests/fixtures/reloadable")
#   (import a from mod ^source "
#     (var $ns/a 1)
#   ")
#   (genex/test/check (a == 1) "Reloadable: precondition failed")
#   (import a from mod ^^reload ^source "
#     (var $ns/a 2)
#   ")
#   (genex/test/check (a == 1))
# """

test_interpreter """
  (var mod "reloadable")
  (import a from mod ^source "
    ($set_reloadable)
    (var $ns/a 1)
  ")
  (genex/test/check (a == 1) "Reloadable: precondition failed")
  ($reload mod "
    (var $ns/a 2)
  ")
  (genex/test/check (a == 2) "Reloadable: reload failed")
"""

# test "Reloadable":
#   init_all()
#   var code = """
#     (var mod "tests/fixtures/reloadable")
#     (var mod_file ("" mod ".gene"))
#     (import a from mod)
#     (if (a != 1) (throw "Reloadable: precondition failed"))
#     (gene/os/exec ("cp " mod_file " /tmp/reloadable.gene"))
#     (gene/File/write mod_file "
#       (var a 2)
#     ")
#     (gene/sleep 100) # wait 0.1 second
#     (try
#       (if (a != 2) (throw "Reloadable: reload failed"))
#     finally
#       (gene/os/exec ("cp /tmp/reloadable.gene " mod_file))
#     )
#   """
#   discard VM.eval(code)
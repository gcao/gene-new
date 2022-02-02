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

# File monitoring should occur in another thread at configured latency
# Communicate with the main thread thru channels?
# https://nim-lang.org/docs/channels_builtin.html

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
  (var b (a + 1))
  (genex/test/check (b == 3))
"""

test_interpreter """
  (var mod "reloadable")
  (import f from mod ^source "
    ($set_reloadable)
    (fn f _ 1)
  ")
  (genex/test/check ((f) == 1) "Reloadable: precondition failed")
  ($reload mod "
    (fn f _ 2)
  ")
  (genex/test/check ((f) == 2))
"""

# test_interpreter """
#   (var mod "tests/fixtures/reloadable")
#   (var mod_file ("" mod ".gene"))
#   (import a from mod)
#   (genex/test/check (a == 1) "Reloadable: precondition failed")
#   (gene/os/exec ("cp " mod_file " /tmp/reloadable.gene"))
#   ($start_monitor)
#   (gene/File/write mod_file "
#     (var $ns/a 2)
#   ")
#   (gene/sleep 2000)
#   (try
#     (genex/test/check (a == 2) "Reloadable: reload failed")
#   finally
#     ($stop_monitor)
#     (gene/os/exec ("cp /tmp/reloadable.gene " mod_file))
#   )
# """

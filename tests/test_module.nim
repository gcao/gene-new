import unittest

import gene/types
import gene/interpreter

import ./helpers

# How module / import works:
# import a, b from "module"
# import from "module" a, b
# import a, b # will import from root's parent ns (which
#    could be the package ns or global ns or a intermediate ns)
# import from "module" a/[b c], d as my_d
# import a # will import from parent, and throw error if "a" not available, this can be useful to make sure the required resource is available when the module is initialized.

test_interpreter """
  (import a from "tests/fixtures/mod1")
  a
""", 1

test_interpreter """
  (import a b from "tests/fixtures/mod1")
  (a + b)
""", 3

test_interpreter """
  (import n from "tests/fixtures/mod1")
  (n/f 1)
""", 1

# test_interpreter """
#   (ns n
#     (fn f _ 1)
#   )
#   (import g from "tests/fixtures/mod2" inherit n)
#   (g)
# """, 1

# # test "Interpreter / eval: import":
# #   init_all()
# #   discard VM.import_module("file1", """
# #     (ns n
# #       (fn f a a)
# #     )
# #   """)
# #   var result = VM.eval """
# #     (import _ as x from "file1")  # Import root namespace
# #     x/f
# #   """
# #   check result.internal.fn.name == "f"

# # test "Interpreter / eval: import":
# #   init_all()
# #   var result = VM.eval """
# #     (import gene/Object)  # Import from parent namespace
# #     Object
# #   """
# #   check result.internal.class.name == "Object"

# test_import_matcher "(import a b from \"module\")", proc(r: ImportMatcherRoot) =
#   check r.from == "module"
#   check r.children.len == 2
#   check r.children[0].name == "a"
#   check r.children[1].name == "b"

# test_import_matcher "(import from \"module\" a b)", proc(r: ImportMatcherRoot) =
#   check r.from == "module"
#   check r.children.len == 2
#   check r.children[0].name == "a"
#   check r.children[1].name == "b"

# test_import_matcher "(import a b/[c d])", proc(r: ImportMatcherRoot) =
#   check r.children.len == 2
#   check r.children[0].name == "a"
#   check r.children[1].name == "b"
#   check r.children[1].children.len == 2
#   check r.children[1].children[0].name == "c"
#   check r.children[1].children[1].name == "d"

# test_import_matcher "(import a b/c)", proc(r: ImportMatcherRoot) =
#   check r.children.len == 2
#   check r.children[0].name == "a"
#   check r.children[1].name == "b"
#   check r.children[1].children.len == 1
#   check r.children[1].children[0].name == "c"

# # test_import_matcher "(import a: my_a b/c: my_c)", proc(r: ImportMatcherRoot) =
# #   check r.children.len == 2
# #   check r.children[0].name == "a"
# #   check r.children[0].as == "my_a"
# #   check r.children[1].name == "b"
# #   check r.children[1].children.len == 1
# #   check r.children[1].children[0].name == "c"
# #   check r.children[1].children[0].as == "my_c"

# test_core """
#   (import gene/Class)
#   (assert ((Class .name) == "Class"))
# """

# test_core """
#   (import gene/*)
#   (assert ((Class .name) == "Class"))
# """

# # test_core """
# #   ($stop_inheritance)
# #   (try
# #     (assert true)  # assert is not inherited any more
# #     1
# #   catch _
# #     2
# #   )
# # """, 2

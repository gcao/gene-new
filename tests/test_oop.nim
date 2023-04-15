import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

# OOP:
#
# * Single inheritance
# * private / protected / public methods
# * method_missing - can only be defined in classes
# * Mixin: all stuff in mixin are copied to the target class/mixin
# * Properties: just a shortcut for defining .prop/.prop= methods

# TODO: test remove_method

test_interpreter "(class A)", proc(r: Value) =
  check r.class.name == "A"

test_interpreter """
  (class A)
  (new A)
""", proc(r: Value) =
  check r.instance_class.name == "A"

test_interpreter """
  (ns n
    (ns m)
  )
  (class n/m/A)
  n/m/A/.name
""", "A"

test_interpreter """
  (class A
    (method init _
      (/p = 1)
    )
  )
  (var a (new A))
  a/p
""", 1

test_interpreter """
  (ns n)
  (class n/A)
  n/A
""", proc(r: Value) =
  check r.class.name == "A"

test_interpreter """
  (class A
    (method test _
      1
    )
  )
  ((new A).test)
""", 1

test_interpreter """
  (class A
    (method test _
      (/a ||= 1)
    )
  )
  ((new A).test)
""", 1

test_interpreter """
  (class A
    # gene/native/test is defined in tests/helpers.nim:init_all()
    (method test = gene/native/test)
  )
  ((new A).test)
""", 1

test_interpreter """
  (class A
    (method init _
      (/a = 1)
    )
    # gene/native/test2 is defined in tests/helpers.nim:init_all()
    (method test2 = gene/native/test2)
  )
  ((new A).test2 2 3)
""", 6

test_interpreter """
  (class A
    (method test _
      (f)
    )
    (fn f _
      1
    )
  )
  ((new A).test)
""", 1

test_interpreter """
  (class A)
""", proc(r: Value) =
  check r.class.parent == VM.object_class.class

test_interpreter """
  (class A)
  ((new A).to_s) # inherit to_s from Object
""", proc(r: Value) =
  check r.str.len > 0

test_interpreter """
  (class A
    (method test _
      (. f)
    )
    (fn f _
      self
    )
  )
  ((new A).test)
""", proc(r: Value) =
  check r.instance_class.name == "A"

test_interpreter """
  (class A
    (method init []
      (/description = "Class A")
    )
  )
  (new A)
""", proc(r: Value) =
  check r.instance_props["description"] == "Class A"

test_interpreter """
  (class A
    (method init []
      (/description = "Class A")
    )
  )
  ((new A) ./description)
""", "Class A"

test_interpreter """
  (class A
    (method init description
      (/description = description)
    )
  )
  ((new A "test") ./description)
""", "test"

test_interpreter """
  (class A
    (method init /name
    )
  )
  ((new A 1)./name)
""", 1

test_interpreter """
  (class A
    (method init /p
    )
    (method test _
      /p
    )
  )
  ((new A 1).test)
""", 1

test_interpreter """
  (class A
    (method test /name
    )
  )
  (var a (new A))
  (a .test 1)
  a/name
""", 1

test_interpreter """
  (class A
    (method test /name
    )
  )
  (var a (new A))
  (a . "test" 1)
  a/name
""", 1

test_interpreter """
  (class A
    (method init [/name = 1]
    )
  )
  ((new A)./name)
""", 1

test_interpreter """
  (class A
    (method init [/p = 1]
    )
    (method test _
      /p
    )
  )
  ((new A).test)
""", 1

# test_interpreter """
#   (class A
#     (method init _
#       ($set_prop "data" {^p 1})
#     )
#     (method test _
#       (($get_prop "data") ./p)
#     )
#   )
#   (var a (new A))
#   a/.test
# """, 1

test_interpreter """
  (class A
    (method init [/p = 1]
    )
  )
  ((new A)./p)
""", 1

test_interpreter """
  (class A
    (method test /x...
    )
  )
  (var a (new A))
  (a . "test" 1 2)
  a/x
""", @[1, 2]

# test_interpreter """
#   (class A
#     (method init ^/name
#     )
#   )
#   ((new A ^name "x")./name)
# """, "x"

# test_interpreter """
#   (class A
#     (method init ^/name ^/...
#       # All properties except name are added to the instance
#     )
#   )
#   ((new A ^prop "x")./prop)
# """, "x"

# test_interpreter """
#   (class A
#     (method init ^/name ^/x...
#       # All properties except name are added to the instance as x
#     )
#   )
#   (((new A ^prop 1)./x)./prop)
# """, 1

test_interpreter """
  (class A
    (method test a
      a
    )

    (method test2 a
      (.test a)
    )
  )
  ((new A).test2 1)
""", 1

test_interpreter """
  (class A
    (method test [a b]
      (a + b)
    )
  )
  ((new A) .test 1 2)
""", 3

test_interpreter """
  (fn f _ 1)
  (class A
    (method test _
      (f)
    )
  )
  ((new A) .test)
""", 1

test_interpreter """
  (fn f _ 1)
  (class A
    (fn g _
      (f)
    )
    (method test _
      (g)
    )
  )
  ((new A) .test)
""", 1

test_interpreter """
  (fn f _ 1)
  (class A
    (var /x
      (f)
    )
    (method test _
      x
    )
  )
  ((new A) .test)
""", 1

# test_interpreter """
#   (fn f _ 1)
#   (class A
#     (var /x
#       (/f) # A's parent namespace should be the module namespace!
#     )
#     (method test _
#       x
#     )
#   )
#   ((new A) .test)
# """, 1

test_interpreter """
  (class A
    (method test []
      "A.test"
    )
  )
  (class B < A
  )
  ((new B) .test)
""", "A.test"

# test_interpreter """
#   (class A
#     (method test _
#       $args
#     )
#   )
#   ((new A) .test 1)
# """, proc(r: Value) =
#   todo()

test_interpreter """
  (class A
    (method test a
      a
    )
  )
  (class B < A
    (method test a
      (super a)
    )
  )
  ((new B) .test 1)
""", 1

test_interpreter """
  (class A
    (method init _
      (/test = 1)
    )
  )
  (class B < A)
  ((new B)./test)
""", 1

test_interpreter """
  (mixin M
    (method test _
      1
    )
  )
  (class A
    (include M)
  )
  ((new A) .test)
""", 1

test_interpreter """
  (mixin M1
    (method test _
      1
    )
  )
  (mixin M2
    (include M1)
  )
  (class A
    (include M2)
  )
  ((new A) .test)
""", 1

test_interpreter """
  ([] .is Array)
""", true

# # Single inheritance with flexibility of changing class, overwriting methods
# # test_interpreter """
# #   (class A
# #     (method test _
# #       1
# #     )
# #   )
# #   (class B
# #     (method test _
# #       2
# #     )
# #   )
# #   (var a (new A))
# #   ((cast a B) .test)
# # """, 2

# # test_interpreter """
# #   (class A
# #     (method test _
# #       1
# #     )
# #   )
# #   (class B
# #     (method test _
# #       2
# #     )
# #   )
# #   (var a (new A))
# #   ((a as
# #     (class < B
# #       (method test _
# #         3
# #       )
# #     )
# #    ) .test)
# # """, 3

# test "Interpreter / eval: native method":
#   init_all()
#   VM.app.ns["test_fn"] = proc(self: Value, props: Table[string, Value], children: seq[Value]): Value =
#     children[0].int + children[1].int
#   var code = cleanup """
#     (class A
#       (native_method test test_fn)
#     )
#     ((new A) .test 1 2)
#   """
#   check VM.eval(code) == 3

# test_core """
#   (macro my_class [name rest...]
#     # Get super class
#     (var super_class
#       (if ((rest .get 0) == :<)
#         (rest .del 0)
#         (caller_eval (rest .del 0))
#       else
#         gene/Object
#       )
#     )
#     # Create class
#     (var cls (gene/Class/new name super_class))

#     # Define member in caller's context
#     (caller_eval (:$def_ns_member name cls))

#     # Evaluate body
#     (for item in rest
#       (eval ^self cls item)
#     )
#     cls
#   )
#   (my_class "A"
#     (method init []
#       (/description = "Class A")
#     )
#   )
#   ((new A) ./description)
# """, proc(r: Value) =
#   check r.str == "Class A"

# test_interpreter """
#   (object Config)
# """, proc(r: Value) =
#   check r.internal.instance_class.name == "ConfigClass"

# test_interpreter """
#   (class A
#     (method test _
#       ("" (./name) ".test")
#     )
#   )
#   (object Config < A
#     (method init _
#       (/name = "Config")
#     )
#   )
#   (Config .test)
# """, "Config.test"

test_interpreter """
  (class A
    (var /children [])
    (.on_extended
      (fnx child
        (/children .add child)
      )
    )
  )
  (class B < A)
  A/children/.size
""", 1

test_interpreter """
  ($object a
    (method test _
      1
    )
  )
  a/.test
""", 1

test_interpreter """
  ($object a
    (method init _
      (/test = 1)
    )

    (method test _
      /test
    )
  )
  a/.test
""", 1

test_interpreter """
  (class A
    (method test _
      1
    )
  )
  ($object a < A
    (method test _
      ((super) + 1)
    )
  )
  a/.test
""", 2

test_interpreter """
  (class A
    (.fn test a
      a
    )
  )
  (var b 1)
  ((new A) .test b)
""", 1

test_interpreter """
  (class A
    (.macro test a
      a
    )
  )
  (var b 1)
  ((new A) .test b)
""", new_gene_symbol("b")

test_interpreter """
  (class A
    (.macro test a
      ($caller_eval a)
    )
  )
  (var b 1)
  ((new A) .test b)
""", 1

# import gene/types

# import ./helpers

# test_interpreter """
#   (class A
#     (method init _
#       ($set_prop "data" {^p 1})
#     )
#     (method get key
#       (($get_prop "data") ./ key)
#     )
#   )
#   (var a (new A))
#   a/p
# """, 1

# test_interpreter """
#   (class A
#     (method init _
#       ($set_prop "data" {^p 1})
#     )
#     (method get key
#       (($get_prop "data") ./ key)
#     )
#     (method set [key value]
#       ($set ($get_prop "data") (@ key) value)
#       value
#     )
#   )
#   (var a (new A))
#   (a/p = 2)
#   a/p
# """, 2

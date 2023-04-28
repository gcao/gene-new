# import gene/types

# import ./helpers

# test_interpreter """
#   (class A
#     (.fn init _
#       ($set_prop "data" {^p 1})
#     )
#     (.fn get key
#       (($get_prop "data") ./ key)
#     )
#   )
#   (var a (new A))
#   a/p
# """, 1

# test_interpreter """
#   (class A
#     (.fn init _
#       ($set_prop "data" {^p 1})
#     )
#     (.fn get key
#       (($get_prop "data") ./ key)
#     )
#     (.fn set [key value]
#       ($set ($get_prop "data") (@ key) value)
#       value
#     )
#   )
#   (var a (new A))
#   (a/p = 2)
#   a/p
# """, 2

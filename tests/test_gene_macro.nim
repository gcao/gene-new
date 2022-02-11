# Support macro language
#
# * Operate on Gene input and system resources (e.g. environment,
#   file system, socket connection, databases, other IO devices etc)
# * Output can be Gene data or string / stream / binary output ?!

# Parser options and macro should not conflict
# Changing parser options in the document are implemented using macros

# Built in functions, variables etc
# #Fn
# #Var
# #Type
# #Props
# #Children
# #Array
# #Map
# #Gene

# #Set
# #Push

# test_parser """
#   (#Fn f _ 1)
#   (#f)
# """, 1

# test_parser """
#   (#Var a [1])
#   #a
# """, @[1]

import gene/types

import ./helpers

# Support macro language
#
# It's hard to create a powerful macro system without making parsing
# very complex. And macro support has to be implemented in all Gene
# parsers. So maybe this is not a good idea!
#
# * Operate on Gene input and system resources (e.g. environment,
#   file system, socket connection, databases, other IO devices etc)
# * Output can be Gene data or string / stream / binary output ?!

# Parser options and macro should not conflict
# Changing parser options in the document are implemented using macros

# Built in functions, variables etc
# #Fn
# #Var

# #Array
# #Map
# #Gene
# #Range
# #Symbol
# #ComplexSymbol

# #If
# #IfNot
# #While
# #Repeat

# #GetType
# #GetProps
# #GetChildren
# #Get
# #Set
# #Add
# #Sub
# #Mul
# #Div
# #Mod
# #Inc
# #Dec

# #And
# #Or
# #Xor
# #Not
# #Eq
# #Ne
# #Le
# #Lt
# #Ge
# #Gt

# #Each
# #Size
# #IsEmpty

# #Push
# #Pop
# #Insert
# #Delete

# #SetParserOption
# #GetParserOption
# #PushParserOption
# #PopParserOption

# #Env
# #Env/HOME

# (#Var x {^name "a"})
# #x/name => a
# (#Set #x/name "b")
# #x/name => b

# test_parser """
#   (#Fn f _ 1)
#   (#f)
# """, 1

# test_parser """
#   (#Var a 1)
#   #a
# """, 1

# Unit conversion
test_parser """
  1m # 1m = 1 minute = 60 seconds (1 = 1s = 1 second)
""", 60
# test_parser """
#   1s
# """, 1
# test_parser """
#   1ms
# """, 0.001
# test_parser """
#   (#Unit "m" 1)  # 1m = 1 meter (meter is defined as the default unit for length)
#   1m
# """, 1
# test_parser """
#   1m30s
# """, 90
# test_parser """
#   1s500ms
# """, 1.5
# test_parser """
#   1m30
# """, 90

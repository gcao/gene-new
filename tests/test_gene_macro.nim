# Support macro language
#
# * Operate on Gene input and system resources (e.g. environment,
#   file system, socket connection, databases, other IO devices etc)
# * Output can be Gene data or string / stream / binary output ?!
# * Namespace: file, function

# Parser options and macro should not conflict
# Changing parser options in the document are implemented using macros

# Built in functions, variables etc

# A parser implementation may support a range of document versions
# #Version # version of the document
# #SetVersion # set version of the document - this should appear near the top of the document,
#               otherwise the parser will assume it's the default version the parser supports.

# #Fn # result of the last expression is returned
# #Return
# #ReturnIf # (#ReturnIf condition result)
# #Void # tell the function to not return a value

# #Throw # should we support catching errors?

# #Import # can add a prefix to all imported functions etc
# #Include

# #Var
# #Const

# #Def # give an ID to a value
# #Ref # refer to the value by its ID

# #Copy
# #DeepCopy

# #Set
# #Get
# #ToString # return a human readable string representation. The format is not strictly defined.
# #Serialize # serialize a Gene value to a string
# #Parse # parse a Gene string to a Gene value
# #ParseJson # parse a JSON string to a Gene value

# Parsing options
# #SetOption
# #GetOption
# #PushOption
# #PopOption

# #Print, #PrintError
# #ReadFromFile, #ReadFromStdin
# #WriteToFile

# #Env
# #Today, #Now

# #If, #IfNot
# #Not
# #And, #Or, #Xor
# #Same
# #Eq, #Neq
# #Lt, #Lte
# #Gt, #Gte

# #Map
# #Each
# #Filter
# #While
# #Loop
# #Yield # Yield a value to the array or the gene's children

# #Break, #BreakIf
# #Continue, #ContinueIf

# Number functions
# #Add, #Sub, #Mul, #Div, #Mod, #Pow
# #Log, #Log2, #Log10, #Ln

# String functions
# #NewString
# #Size
# #IndexOf
# #Contains

# Regex functions
# #NewRegex
# #Match

# Array functions
# #NewArray
# #Sort
# #Insert
# #Append
# #Prepend
# #Delete
# #IndexOf
# #Join

# Map functions
# #NewMap
# #MapKeys
# #MapValues
# #HasKey
# #Delete

# Gene functions
# #NewGene
# #GetType
# #GetProps
# #GetChildren
# #SetType

# Date & time functions

# test_parser """
#   (#Fn #f _ 1)
#   (#f)
# """, 1

# test_parser """
#   (#Var #a [1])
#   #a
# """, @[1]

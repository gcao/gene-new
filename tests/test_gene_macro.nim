# Support macro language
# See https://github.com/gcao/gene/blob/master/spec/gene/gene_macro_interpreter_spec.rb
# for previous implementation as a reference.
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
# #Void   # tell the function to not return a value and the caller should not add
#         # anything to the output.

# #Macro # can be used to define for-loops etc
# E.g.
# (#Macro #for [#name in #list #block...]
#   # logic goes here...
# )
# (#for #x in [1 2 3] (#Println #x))

# Optional argument is supported, but default value is not supported.
# Inside function/macro's body, it can check and set optional argument's value.

# For simplicity's sake, #Fn and #Macro don't support keyword arguments. If a
# key-value map must be passed in, it is recommended to be passed as the first or
# last positional argument.
# E.g.
# (#Fn #f [#first #options]
#   (#Add #first #options/x)
# )
# (#f 1 {^x 2})

# Should we support catching errors? maybe it's required to implement some flows?
# #Throw name "message" # Throw an error that is a subclass of MacroError
# #Throw name
# #Throw "message"
# #Catch * # catch all errors, including the system errors
# #Catch _ # catch all errors thrown by the macro, including the unnamed errors, but not the system errors
# #Catch name
# #Catch [name1, name2]

# #Import # can add a prefix to all imported functions etc.
#         # if no prefix is given, members to be imported must be explicitly specified.

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
# #Serialize # serialize a Gene value to a Gene string
# #Parse # parse a Gene string to a Gene value
# #ParseJson # parse a JSON string to a Gene value

# Maybe we do not rely on parsing options, but using special members in the scope
# to control the behavior of the parser?
# Pro:
#   we don't rely on another complex component to manage the options
# Con:
#   Q: can scope logic change and become incompatible with how options are supposed to work?
#   A: yes it's possible

# Parsing options
# #SetOption
# #ResetOption
# #GetOption
# #PushOption
# #PopOption - called automatically unless it's called explicitly

# #SetOption vs #PushOption
# We need to know whether an option is set or pushed.
# After an option is pushed, we should not allow setting that option any more.
# So SetOption is used for the top level option only.
# PushOption can be used on the top level or any where.
# PopOption is automatically called at the end of a gene / array unless it's
#   explicitly called.
# ResetOption can be called manually to clear the option.

# #Print, #PrintError
# #Println
# #Debug
# #Read # Read from file
# #ReadFromStdin
# #Write # Write to file

# #Params # an optional key value map that is passed while parsing
# #Env
# #Cwd # current working dir
# #Today, #Now

# #If, #IfNot
# #Not
# #And, #Or, #Xor
# #Same
# #Eq, #Neq
# #Lt, #Lte
# #Gt, #Gte

# #While
# #Loop
# #Yield # Yield a value to the array or the gene's children

# #Break, #BreakIf
# #Continue, #ContinueIf

# Number functions
# #Add, #Sub, #Mul, #Div, #Mod, #Pow, #Sqrt
# #Inc, #Dec
# #Log, #Log2, #Log10, #Ln
# #Rand
# #Sin, #Cos, #Tan, #Atan
# #E, #PI

# String functions
# #String/new
# #String/size
# #String/index
# #String/contains

# #Symbol/new

# Regex functions
# #Regex/new
# #Regex/match

# Array functions
# #Array/new
# #Array/sort
# #Array/insert
# #Array/push, #Array/pop
# #Array/prepend
# #Array/delete
# #Array/index
# #Array/join
# #Array/map
# #Array/each
# #Array/filter

# Map functions
# #Map/new
# #Map/keys
# #Map/values
# #Map/hasKey
# #Map/delete
# #Map/each

# Gene functions
# #Gene/new
# #Gene/type
# #Gene/props
# #Gene/children
# #Gene/setType

# Date & time functions

# test_parser """
#   (#Fn #f _ 1)
#   (#f)
# """, 1

# test_parser """
#   (#Var #a [1])
#   #a
# """, @[1]

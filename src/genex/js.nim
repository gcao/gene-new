import ../gene/types
import ../gene/interpreter_base

# Performance is not as critical as the interpreter because this is usually run only once.

# Use macro to generate JavaScript AST nodes
# Then call to_s to convert to JS code

# For complex statement like
# if (cond) {
#   for(var i = 0; i < n; i++) {
#     ...
#   }
# }
# The condition, body of if and else must be evaluated and translated one by one,
# then generated body are added to the output one by one as well.

# Statements vs expressions
# The parent node should know what to expect: statements or expressions.
# to_stmt, to_expr, to_s

# https://lisperator.net/pltut/compiler/js-codegen
# https://tomassetti.me/code-generation/
# https://stackoverflow.com/questions/12703214/javascript-difference-between-a-statement-and-an-expression

# gene/js/
# js: render then translate to AST then call to_s on AST nodes

# literals: nil -> null, true -> true, false -> false, 1 -> 1
# strings:
# undefined: undefined
# [] -> array
# {} -> object
# fn*, fnx*, fnxx* -> function
# if -> if
# if? = (a ? b c) -> a ? b : c
# for -> for
# while -> while
# var -> var
# let -> let
# class -> class
# (1 + 2) -> (1 + 2)  # "(" and ")" will be in the generated code
# (1 + 2 * 3) -> (1 + 2 * 3)
# (f 1 2) -> function call, e.g. f(1, 2)
# a/b, a/b/c -> property get, e.g. a.b, a.b.c
# (a = 1) -> assignment set, e.g. a.b = 1
#
# Special constructs for convenience:
# iife* -> (function(){...})()
# log* -> console.log

proc init*() =
  VmCreatedCallbacks.add proc() =
    discard eval(VM.runtime.pkg, """
      (ns genex/js
        (ns ast
          (class Base
            (.fn to_s _
              ("/* TODO: " /.name " */")
            )
            (.fn to_stmt _
              /.to_s
            )
            (.fn to_expr _
              /.to_s
            )
          )

          (class Unknown < Base
          )

          (class String < Base
            (.ctor /value
            )
            (.fn to_s _
              ('"' (/value .replace '"' '\\"') '"')
            )
          )

          (class Literal < Base
            (.ctor /value
            )
            (.fn to_s _
              /value/.to_s
            )
          )

          (class Array < Base
            (.ctor /children
            )
            (.fn to_s _
              ("[" (/children .join ", ") "]")
            )
          )

          (class Map < Base
            (.ctor /props
            )
            (.fn to_s _
              ("{"
                ((/props .map ([k v] -> ('"' k '": ' v)))
                  .join ", "
                )
              "}")
            )
          )

          # Group of nodes.
          # When generating code, "{}" is not generated by this class.
          # Instead, the parent node is responsible for generating "{}" around code from this class.
          (class Group < Base
            (.ctor [/children = []]
            )
            (.fn empty _
              /children/.empty
            )
            (.fn to_s _
              ("" (/children .join ";\n"))
            )
            (.fn to_expr _
              (not_allowed "JavaScript: Group can not be used as an expression.")
            )
          )

          (class New < Base
            (.ctor [/class /args]
            )
            (.fn to_s _
              #"new #{/class}(#(/args .join ", "))"
            )
          )

          (class Var < Base
            (.ctor [/name /value]
            )
            (.fn to_s _
              ("var " /name (if /value (" = " /value/.to_s)))
            )
            (.fn to_expr _
              (not_allowed "JavaScript: Var can not be used as an expression.")
            )
          )

          (class If < Base
            (.ctor args
              (/if_cond       = nil)
              (/if_logic      = (new Group))
              (/elifs         = [])   # store list of {^cond node ^logic group}
              (/current_elif  = nil)  # store elif pairs that is being parsed
              (/else_logic    = (new Group))
              (.parse args)
            )

            (enum State
              If Cond Logic Elif ElifCond ElifLogic Else
            )
            (.fn handle input
              (case /state
              when State/If
                (/if_cond = (translate input))
                (/state = State/Cond)
              when State/Cond
                (/if_logic/children .add (translate input))
                (/state = State/Logic)
              when State/Logic
                (case input
                when :else
                  (/state = State/Else)
                when :elif
                  (/state = State/Elif)
                else
                  (/if_logic/children .add (translate input))
                )
              when State/Else
                (/else_logic/children .add (translate input))
              )
            )
            (.fn parse args
              (/state = State/If)
              (for arg in args
                (.handle arg)
              )
            )

            (.fn to_s _
              ("if (" /if_cond ") {\n"
                /if_logic
                "\n}"
                (if not /else_logic/.empty
                  ("else {\n"
                    /else_logic
                  "\n}")
                )
              )
            )
            (.fn to_expr _
              (not_allowed "JavaScript: If can not be used as an expression.")
            )
          )

          (class Ternary < Base
            (.ctor [/cond /true_value /false_value]
            )
            (.fn to_s _
              ("("
                /cond " ? " /true_value " : " /false_value
              ")")
            )
          )

          # This is not a valid AST node. Replace with more appropriate one like
          # Arithmatic node (a + b * c)
          # Logical node (a && b || c)
          # Assignment node (a = b) (a += b)
          # ...
          (class JoinableExpr < Base
            (.ctor /children
            )
            (.fn to_s _
              ("("
                (/children .join " ")
              ")")
            )
          )

          (class JoinStrings < Base
            (.ctor /children
            )
            (.fn to_s _
              ("("
                (/children .join " + ")
              ")")
            )
          )

          (class Function < Base
            (.ctor [/name args body]
              (if (args .is gene/Array)
                (/args = args)
              elif (args != _)
                (/args = [args])
              )
              (/body = (new Group body))
            )
            (.fn to_s _
              ("function " /name "(" (/args .join ", ") ") {\n"
                /body
              "\n}")
            )
          )

          (class Return < Base
            (.ctor /value
            )
            (.fn to_s _
              ("return " /value ";\n")
            )
          )

          (class Call < Base
            (.ctor [/fn /args]
            )
            (.fn to_s _
              ("" /fn "(" (/args .join ", ") ")")
            )
          )

          (class AccessBy < Base
            (.ctor /by
            )
            (.fn to_s _
              ("[" /by "]")
            )
          )

          (class Println < Base
            (.ctor /args)

            (.fn to_s _
              ("console.log("
                (/args .join ", ")
              ");")
            )
          )
        )

        (macro js nodes...
          (var code ((nodes .map translate) .join ";\n"))
          (var uglify ($env "GENE_UGLIFY_JS"))
          (if uglify
            (var file "/tmp/generated.js")
            (gene/File/write file code)
            (var uglified "/tmp/generated.uglified.js")
            (gene/os/exec ("" uglify " -b width=120 " file " > " uglified))
            (code = (gene/File/read uglified))
          )
          code
        )

        (fn translate_bin value
          (var children [(translate value/.type)])
          (for item in value/.children
            (children .add (translate item))
          )
          (new ast/JoinableExpr children)
        )

        (fn translate_new value
          (var class value/.children/0)
          (var args [])
          (var i 1)
          (while (i < value/.children/.size)
            (args .add (translate (value ./ i)))
            (i += 1)
          )
          (new ast/New class args)
        )

        (fn translate_if value
          (new ast/If value/.children)
        )

        (fn translate_ternary value
          (new ast/Ternary
            (translate value/0)
            (translate value/1)
            (translate value/2)
          )
        )

        (fn translate_fn value
          (var body [])
          (var i 2)
          (while (i < value/.children/.size)
            (body .add (translate (value ./ i)))
            (i += 1)
          )
          (new ast/Function value/0 value/1 body)
        )

        (fn translate_fnx value
          (var body [])
          (var i 1)
          (while (i < value/.children/.size)
            (body .add (translate (value ./ i)))
            (i += 1)
          )
          (new ast/Function "" value/0 body)
        )

        (fn translate_symbol value
          (var symbol value/.to_s)
          (if (symbol .starts_with "@")
            (var s (symbol .substr 1))
            (if (s =~ #/^\d+$/)
              (new ast/AccessBy (new ast/Literal s/.to_i))
            else
              (new ast/AccessBy (new ast/String s))
            )
          elif (symbol .contains ".")
            (var s "")
            (for [i part] in (symbol .split ".")
              (if (i == 0)
                (s .append part)
              elif (part =~ #/^\d+$/)
                (s .append "[" part "]")
              else
                (s .append "." part)
              )
            )
            (new ast/Literal s)
          else
            (new ast/Literal value)
          )
        )

        (fn translate_gene value
          (var first value/0)
          (if (first .is Symbol)
            (var symbol first/.to_s)
            (if (symbol .starts_with ".")
              (var children [(translate value/.type)])
              (for item in value/.children
                (children .add (translate item))
              )
              (return (new ast/JoinableExpr children))
            elif (symbol .starts_with "@")
              (if (symbol/.size == 1) # (x @ y) -> x[y]
                (var children [(translate value/.type) (new ast/AccessBy (translate value/1))])
                (return (new ast/JoinableExpr children))
              else
                (var children [(translate value/.type)])
                (for item in value/.children
                  (children .add (translate item))
                )
                (return (new ast/JoinableExpr children))
              )
            )
          )
          (case first
          when :=
            (translate_bin value)
          when [:+ :- :* :/ :== :&& :||]
            (translate_bin value)
          else
            (case value/.type
            when String
              (var children [(translate value/.type)])
              (for item in value/.children
                (if (item == :+)
                  (not_allowed "+ is not allowed, use \"+\" if necessary")
                else
                  (children .add (translate item))
                )
              )
              (new ast/JoinStrings children)
            when :var
              (new ast/Var first
                (if (value/.children/.size > 1)
                  (translate value/1)
                )
              )
            when :new
              (translate_new value)
            when :if
              (translate_if value)
            when :?
              (translate_ternary value)
            when :fn*
              (translate_fn value)
            when :fnx*
              (translate_fnx value)
            else
              # function call
              (var children (value/.children .map translate))
              (new ast/Call (translate value/.type) children)
            )
          )
        )

        (fn translate value
          (case value
          when ast/Base   # already translated
            value
          when [Int Bool]
            (new ast/Literal value)
          when Symbol
            (translate_symbol value)
          when String
            (new ast/String value)
          when Array
            (var children (value .map translate))
            (new ast/Array children)
          when Map
            (for [k v] in value
              ($set value k (translate v))
            )
            (new ast/Map value)
          when Gene
            (translate_gene value)
          else
            (todo ("translate " value))
          )
        )
      )
    """)

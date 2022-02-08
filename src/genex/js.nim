import ../gene/types
import ../gene/interpreter_base

# Performance is not as critical as the interpreter because this is usually run only once.

# Use macro to generate JavaScript AST nodes
# Then call to_s to convert to JS code

# Statements vs expressions
# The parent node should know what to expect: statements or expressions.
# to_stmt, to_expr, to_s

# https://lisperator.net/pltut/compiler/js-codegen
# https://tomassetti.me/code-generation/
# https://stackoverflow.com/questions/12703214/javascript-difference-between-a-statement-and-an-expression

# gene/js/
# js: call to_s on nodes
# literals: Nil -> null, true -> true, false -> false
# undefined: undefined
# array -> array
# map -> object
# fn* -> function
# if* -> if
# if? = (a ? b c) -> a ? b : c
# for* -> for
# while* -> while
# var* -> var
# let* -> let
# class* -> class
# (1 + 2) -> (1 + 2)  # "(" and ")" will be in the generated code
# (1 + 2 * 3) -> (1 + 2 * 3)
# (:f 1 2) -> function call, e.g. f(1, 2)
# :a/b, :a/b/c -> property get, e.g. a.b, a.b.c
# (:a/b = 1) -> property set, e.g. a.b = 1
# iife -> (function(){...})()
# println* -> console.log

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    discard self.eval(self.runtime.pkg, """
      (ns genex/js
        (ns ast
          (class Base
            (method to_s _
              ("/* TODO: " /.name " */")
            )
            (method to_stmt _
              /.to_s
            )
            (method to_expr _
              /.to_s
            )
          )

          (class Unknown < Base
          )

          (class String < Base
            (method new @value
            )
            (method to_s _
              ('"' (/@value .replace '"' '\\"') '"')
            )
          )

          (class Literal < Base
            (method new @value
            )
            (method to_s _
              /@value/.to_s
            )
          )

          (class Array < Base
            (method new @children
            )
            (method to_s _
              ("[" (/@children .join ", ") "]")
            )
          )

          (class Map < Base
            (method new @props
            )
            (method to_s _
              ("{"
                (
                  (/@props .map ([k v] -> ('"' k '": ' v)))
                  .join ", "
                )
              "}")
            )
          )

          # Group of nodes.
          # When generating code, "{}" is not generated by this class.
          # Instead, the parent node is responsible for generating "{}" around code from this class.
          (class Group < Base
            (method new [@children = []]
            )
            (method empty _
              /@children/.empty
            )
            (method to_s _
              ("" (/@children .join ";\n"))
            )
            (method to_expr _
              (not_allowed "JavaScript: Group can not be used as an expression.")
            )
          )

          (class Var < Base
            (method new [@name @value]
            )
            (method to_s _
              ("var " /@name (if /@value (" = " /@value/.to_s)))
            )
            (method to_expr _
              (not_allowed "JavaScript: Var can not be used as an expression.")
            )
          )

          (class If < Base
            (method new args
              (@if_cond       = nil)
              (@if_logic      = (new Group))
              (@elifs         = [])   # store list of {^cond node ^logic group}
              (@current_elif  = nil)  # store elif pairs that is being parsed
              (@else_logic    = (new Group))
              (.parse args)
            )

            (enum State
              If Cond Logic Elif ElifCond ElifLogic Else
            )
            (method handle input
              (case /@state
              when State/If
                (@if_cond = (translate input))
                (@state = State/Cond)
              when State/Cond
                (/@if_logic/@children .add (translate input))
                (@state = State/Logic)
              when State/Logic
                (case input
                when :else
                  (@state = State/Else)
                when :elif
                  (@state = State/Elif)
                else
                  (/@if_logic/@children .add (translate input))
                )
              when State/Else
                (/@else_logic/@children .add (translate input))
              )
            )
            (method parse args
              (@state = State/If)
              (for arg in args
                (.handle arg)
              )
            )

            (method to_s _
              ("if (" /@if_cond ") {\n"
                /@if_logic
                "\n}"
                (if not /@else_logic/.empty
                  ("else {\n"
                    /@else_logic
                  "\n}")
                )
              )
            )
            (method to_expr _
              (not_allowed "JavaScript: If can not be used as an expression.")
            )
          )

          (class Println < Base
            (method new @args)

            (method to_s _
              ("console.log("
                (/@args .join ", ")
              ");")
            )
          )
        )

        (fn /js nodes...
          (nodes .join ";\n")
        )

        (fn /translate value
          (case value/.class
          when ast/Base   # already translated
            value
          when [Int Bool Symbol]
            (new ast/Literal value)
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
            (eval value)
          else
            (todo ("translate " value))
          )
        )

        (macro var* [name value = nil]
          (new ast/Var
            name
            (if value
              (translate ($caller_eval value))
            )
          )
        )

        (macro if* args...
          (new ast/If args)
        )

        (fn println* args...
          (new ast/Println (args .map translate))
        )
      )
    """)

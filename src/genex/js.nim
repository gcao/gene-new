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

          (class Array < Base # since Array is conflict with gene/Array, it should be referenced as ast/Array
            (method new @children...
            )
            (method to_s _
              ("[" (/@children .join ", ") "]")
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

          (class Println < Base
            (method new @args...)

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
          when Array
            (var children (value .map translate))
            (new ast/Array children...)
          when [Int Bool Symbol]
            (new ast/Literal value)
          when String
            (new ast/String value)
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

        (fn println* args...
          (new ast/Println (... (args .map translate)))
        )
      )
    """)

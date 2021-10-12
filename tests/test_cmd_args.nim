import unittest, tables

import gene/types
import gene/parser
import gene/features/parse_cmd_args

import ./helpers

# Command line arguments matching
#
# Program:   program, usually the first argument
# Option:    prefixed with "-" or "--"
# Primary:
# Secondary: after "--"
#
# Required vs optional
# Toggle vs value expected
# Single vs multiple values
#
# -l --long
# -l x -l y -l z  OR -l x,y,z
# xyz
# -- x y z

# Input:   seq[string] or string(raw arguments string)
# Schema:
# Result:

# [
#   program
#   (option   ^^toggle -t "description")                 # "t" will be used as key
#   (option   ^^required ^^multiple ^type int -l --long) # "--long" will be used as key
#   (argument ^type int name "description")              # "name" will be used as key
#   (argument ^^multiple ^type int name)                 # "name" will be used as key
# ]

# (WIP)
# ($parse_cmd_args
#   [
#     program   # program will be the property that contains the name of the script/program
#
#     (toggle -d --debug)
#
#     (list -i --include)             # Can contain 0 to many items, "-i 1 -i 2"
#     (list ^^required -i --include)  # Must contain at least one item
#
#     (opt -r --run)                  # Not mandatory option, expect one value
#     (opt ^^required -r --run)
#
#     (arg file)                      # Required by default
#     (arg ^!required file)
#
#     (list files)                    # Can contain 0 to many item
#   ]
#   $cmd_args   # The global variable that holds the command line argument array
# ) # Return a map

proc test_args*(schema, input: string, callback: proc(r: ArgMatchingResult)) =
  var schema = cleanup(schema)
  var input = cleanup(input)
  test schema & "\n" & input:
    var m = new_cmd_args_matcher()
    m.parse(read(schema))
    var r = m.match(input)
    callback r

test_args """
  [
    (option ^^toggle -t --toggle)
  ]
""", """
""", proc(r: ArgMatchingResult) =
  check r.kind == AmSuccess
  check r.options.len == 1
  check r.options["--toggle"] == False

test_args """
  [
    (argument first)
  ]
""", """
""", proc(r: ArgMatchingResult) =
  check r.kind == AmSuccess
  check r.args.len == 1
  check r.args["first"] == ""

test_args """
  # Test extra arguments after "--"
  [
  ]
""", """
  -- one two
""", proc(r: ArgMatchingResult) =
  check r.kind == AmSuccess
  check r.extra == @["one", "two"]

test_args """
  [
    (option -l --long)
    (option ^^toggle -t --toggle)
    (argument first)
  ]
""", """
  -l long-value one
""", proc(r: ArgMatchingResult) =
  check r.kind == AmSuccess
  check r.options.len == 2
  check r.options["--long"] == "long-value"
  check r.options["--toggle"] == False
  check r.args.len == 1

test_args """
  [
    (option -l --long)
    (option ^^toggle -t --toggle)
    (argument first)
  ]
""", """
  -l long-value one
""", proc(r: ArgMatchingResult) =
  check r.kind == AmSuccess
  check r.fields.len == 3
  check r.fields["--long"] == "long-value"
  check r.fields["--toggle"] == False # use False instead of false because "check" does not like bool == bool
  check r.fields["first"] == "one"

test_args """
  [
    program
    (option -l --long)
    (option ^^multiple -m)
    (argument first)
    (argument ^^multiple second)
  ]
""", """
  my-script -l long-value -m m1,m2 one two three
""", proc(r: ArgMatchingResult) =
  check r.kind == AmSuccess
  check r.program == "my-script"
  check r.options.len == 2
  check r.options["--long"] == "long-value"
  check r.options["-m"] == @[new_gene_string("m1"), new_gene_string("m2")]
  check r.args.len == 2
  check r.args["first"] == "one"
  check r.args["second"] == @[new_gene_string("two"), new_gene_string("three")]

test_args """
  [
    (option ^type bool -b)
    (option ^type int -i)
    (option ^type int ^^multiple -m)
    (argument ^type bool first)
    (argument ^type int second)
    (argument ^type int ^^multiple third)
  ]
""", """
  -b true -i 1 -m 2,3 true 1 2 3
""", proc(r: ArgMatchingResult) =
  check r.kind == AmSuccess
  check r.options.len == 3
  check r.options["-b"]
  check r.options["-i"] == 1
  check r.options["-m"] == @[new_gene_int(2), new_gene_int(3)]
  check r.args.len == 3
  check r.args["first"]
  check r.args["second"] == 1
  check r.args["third"] == @[new_gene_int(2), new_gene_int(3)]

test_args """
  # Test default values
  [
    (option ^type bool ^default true -b)
    (option ^type int ^default 10 -i)
    (option ^type int ^default [20 30] ^^multiple -m)
    (argument ^type int ^default [100 200] ^^multiple first)
  ]
""", "", proc(r: ArgMatchingResult) =
  check r.kind == AmSuccess
  check r.options.len == 3
  check r.options["-b"]
  check r.options["-i"] == 10
  check r.options["-m"] == @[new_gene_int(20), new_gene_int(30)]
  check r.args.len == 1
  check r.args["first"] == @[new_gene_int(100), new_gene_int(200)]

test_interpreter """
  ($parse_cmd_args  # parse arguments and define members in current scope
    [
      (option ^type bool -b)
      (option ^type int -i)
      (option ^type int ^^multiple -m)
      (argument ^type bool first)
      (argument ^type int second)
      (argument ^type int ^^multiple third)
    ]
    ["-b" "true" "-i" "1" "-m" "2,3" "true" "1" "2" "3"]
  )
  (assert b)
  (assert (i == 1))
  (assert (m == [2 3]))
  (assert first)
  (assert (second == 1))
  (assert (third == [2 3]))
"""

test_interpreter """
  ($parse_cmd_args  # parse arguments and define members in current scope
    [
      program
      (option ^^toggle -d --debug)
      (option -r --run)
      (argument ^!required file)
    ]
    ["program" "-r" "test"]
  )
  (assert (run == "test"))
"""

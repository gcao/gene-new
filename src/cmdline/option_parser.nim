import parseopt, os

import ../gene/types

type
  InputMode* = enum
    ImDefault
    ImCsv
    ImGene
    ImLine

  Options* = ref object
    debugging*: bool
    repl*: bool
    repl_on_error*: bool
    file*: string
    eval*: string
    # snippets are wrapped like (do <snippet>) and can be accessed from anywhere
    snippets*: seq[string]
    # `include` is different from `import`.
    # `include` is like inserting content of one file in another.
    includes*: seq[string]
    args*: seq[string]
    benchmark*: bool
    print_result*: bool
    filter_result*: bool
    input_mode*: InputMode
    skip_first*: bool
    skip_empty*: bool
    index_name*: string
    value_name*: string

let shortNoVal = {'d'}
let longNoVal = @[
  "repl-on-error",
  "debug",
  "benchmark",
  "print-result", "pr",
  "filter-result", "fr",
  "skip-first-line", "sf",
  "skip-empty-line", "se",
  "csv",
  "gene",
  "line",
]

# When running like
# <PROGRAM> --debug test.gene 1 2 3
# test.gene is invoked with 1, 2, 3 as argument
#
# When running like
# <PROGRAM> --debug -- 1 2 3
# 1, 2, 3 are passed as argument to REPL
proc parseOptions*(): Options =
  result = Options(
    repl: true,
    index_name: "i",
    value_name: "v",
  )
  var expect_args = false
  # Stop parsing options once we see arguments
  var in_arguments = false
  for kind, key, value in getOpt(commandLineParams(), shortNoVal, longNoVal):
    case kind
    of cmdArgument:
      in_arguments = true
      if expect_args:
        result.args.add(key)
      else:
        expect_args = true
        result.repl = false
        result.file = key

    of cmdLongOption, cmdShortOption:
      if in_arguments:
        continue
      if expect_args:
        result.args.add(key)
        result.args.add(value)
      case key
      of "eval", "e":
        result.repl = false
        result.eval = value
      of "snippet", "s":
        result.snippets.add(value)
      of "include":
        result.includes.add(value)
      of "debug", "d":
        result.debugging = true
      of "benchmark":
        result.benchmark = true
      of "print-result", "pr":
        result.print_result = true
      of "filter-result", "fr":
        result.filter_result = true
      of "index-name", "in":
        result.index_name = value
      of "value-name", "vn":
        result.value_name = value
      of "input-mode", "im":
        case value:
        of "csv":
          result.input_mode = ImCsv
        of "gene":
          result.input_mode = ImGene
        # of "line":
        #   result.input_mode = ImLine
        else:
          raise new_exception(ArgumentError, "Invalid input-mode: " & value)
      of "csv":
        result.input_mode = ImCsv
      of "gene":
        result.input_mode = ImGene
      of "line":
        result.input_mode = ImLine
      of "skip-first-line", "sf":
        result.skip_first = true
      of "skip-empty-line", "se":
        result.skip_empty = true
      of "repl-on-error":
        result.repl_on_error = true
      of "":
        expect_args = true
      else:
        echo "Unknown option: ", key
        discard

    of cmdEnd:
      discard

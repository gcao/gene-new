import strutils

# Nimble does not support path to dependency yet
include ../../../../src/gene/extension/boilerplate

{.push dynlib exportc.}

proc upcase(args: Value): Value {.wrap_exception.} =
  return args.gene_data[0].str.to_upper()

{.pop.}

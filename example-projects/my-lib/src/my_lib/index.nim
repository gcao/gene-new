import strutils

# Nimble does not support path to dependency yet
include ../../../../src/gene/extension/boilerplate

{.push dynlib exportc.}

proc upcase(args: seq[Value]): Value =
  return args[0].str.to_upper()

{.pop.}

import strutils

# Nimble does not support path to dependency yet
import ../../../../src/gene/types

{.push dynlib exportc.}

proc upcase(args: seq[GeneValue]): GeneValue =
  return args[0].str.to_upper()

{.pop.}

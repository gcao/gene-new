import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

test_core """
  ((nil .class).name)
""", "Nil"

test_core """
  (var sum 0)
  (4 .times (i -> (sum += i)))
  sum
""", 6 # 0 + 1 + 2 + 3

# CSV separated by \t
# first\tsecond
# 1\t2
# 10\t20
test_core "(gene/csv/parse_string \n\"first\tsecond\n1\t2\n10\t20\")", @[
  new_gene_vec(@["1", "2"]),
  new_gene_vec(@["10", "20"]),
]

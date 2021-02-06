import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

test_core """
  (gene/Class .name)
""", "Class"

test_core """
  ((gene/String .parent).name)
""", "Object"

import unittest, tables

import gene/types
import gene/interpreter

import ./helpers

test_interpreter """
  (gene/Class .name)
""", "Class"

test_interpreter """
  ((gene/String .parent).name)
""", "Object"

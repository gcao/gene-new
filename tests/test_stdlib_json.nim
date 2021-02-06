import unittest, tables, os, osproc

import gene/types
import gene/interpreter

import ./helpers

test_core """
  (gene/json/parse
    "{\"a\": true}"
  )
""", {"a": GeneTrue}.toOrderedTable

test_core """
  ([1 2].to_json)
""", "[1,2]"

import unittest, tables, os, osproc

import gene/types
import gene/interpreter

import ./helpers

test_interpreter """
  (gene/json/parse
    "{\"a\": true}"
  )
""", {"a": True}.toOrderedTable

test_interpreter """
  ([1 2].to_json)
""", "[1,2]"

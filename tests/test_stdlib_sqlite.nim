import unittest

import gene/types
import gene/parser
import gene/interpreter

import ./helpers

# Create db
# Create/recreate table
# Drop table
# Open/close db connection
# Insert
# Select
#   E.g. SELECT a.*, TRIM(b.name) AS name
#        FROM table_a a
#        JOIN table_b b ON a.id=b.id
#        WHERE a.id IN (...)
#        ORDER BY b DESC
# Update
# Delete

proc test_sql(code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    callback read(code)

suite "SQLite":
  init_all()
  discard VM.eval("""
    # Recreate sqlite db
    (import from "build/libsqlite" ^^native)
  """)

  test_sql """
    (genex/select * from test)
  """, proc(r: Value) =
    todo()

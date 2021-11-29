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
#   E.g. INSERT INTO t(...)
#        VALUES
#          (...),
#          (...)
# Select
#   E.g. SELECT a.*, TRIM(b.name) AS name
#        FROM table_a a
#        JOIN table_b b ON a.id=b.id
#        WHERE a.id IN (...)
#        GROUP BY a.type
#        HAVING SUM(a.amount) > 100
#        ORDER BY b DESC
# Update
#   E.g. UPDATE t
#        SET name=UPPER(name)
#        WHERE ...
# Delete
#   E.g. DELETE FROM t
#        WHERE ...

var db_file = "/tmp/gene-test.db"

proc test_sql(code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    callback read(code)

suite "SQLite":
  init_all()
  discard VM.eval("""
    (import from "build/libsqlite" ^^native)
  """)

  setup:
    # Recreate sqlite db
    exec "rm " & db_file
    let db = open(db_file, "", "", "")
    db.exec(sql"""
      DROP TABLE IF EXISTS table_a
    """)
    db.exec(sql"""
      CREATE TABLE table_a (
        id   INTEGER,
        name VARCHAR(50) NOT NULL
      )
    """)
    db.exec(sql"""
      INSERT INTO my_table (id, name) VALUES (1, 'John')
      INSERT INTO my_table (id, name) VALUES (2, 'Mark')
    """)
    db.close()

  test_sql """
    (var db (genex/sqlite/open "/tmp/gene-test.db"))
    (db .exec (genex/sqlite/select * from table_a))
  """, proc(r: Value) =
    check r.vec.len == 2

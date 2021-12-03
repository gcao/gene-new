import osproc, db_sqlite
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

proc test_sql(code: string) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    discard VM.eval(code)

proc test_sql(code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Interpreter / eval: " & code:
    callback VM.eval(code)

proc recreate_db() =
  discard exec_cmd_ex "rm " & db_file
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
    INSERT INTO table_a (id, name)
    VALUES (1, 'John'),
           (2, 'Mark')
  """)
  db.close()

suite "SQLite":
  recreate_db()
  init_all()

  test_sql """
    (var db (genex/sqlite/open "/tmp/gene-test.db"))
    (db .close)
  """

  test_sql """
    (var db (genex/sqlite/open "/tmp/gene-test.db"))
    (var rows (db .exec "select * from table_a"))
    (db .close)
    rows
  """, proc(r: Value) =
    check r.vec.len == 2
    check r.vec[0].vec[0] == "1"
    check r.vec[0].vec[1] == "John"

  # test_sql """
  #   (try
  #     (var db (genex/sqlite/open "/tmp/gene-test.db"))
  #     (db .exec :(select * from table_a))
  #   finally
  #     (db .close)
  #   )
  # """, proc(r: Value) =
  #   check r.vec.len == 2

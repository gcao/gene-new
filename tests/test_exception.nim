import gene/types

import ./helpers

# Native Nim exception vs Gene exception:
# Nim exceptions can be accessed from nim/ namespace
# Nim exceptions should be translated to Gene exceptions eventually
# Gene core exceptions are defined in gene/ namespace
# Gene exceptions share same Nim class: GeneException
# For convenience purpose all exception classes like gene/XyzException are aliased as XyzException

# Retry support - from the beginning of try?
# (try...catch...(retry))

# (throw)
# (throw message)
# (throw Exception)
# (throw Exception message)
# (throw (new Exception ...))

# (try...catch...catch...finally)
# (try...finally)
# (fn f []  # converted to (try ...)
#   ...
#   catch ExceptionX ...
#   catch _ ...
#   finally ...
# )

# test "(throw ...)":
#   var code = """
#     (throw "test")
#   """.cleanup
#   test "Interpreter / eval: " & code:
#     init_all()
#     discard VM.eval(code)
#     # try:
#     #   discard VM.eval(code)
#     #   check false
#     # except:
#     #   discard

test_core """
  (try
    (throw)
    1
  catch _
    2
  )
""", 2

test_core """
  (class TestException < Exception)
  (try
    (throw TestException)
    1
  catch TestException
    2
  catch _
    3
  )
""", 2

test_core """
  (class TestException < Exception)
  (try
    (throw)
    1
  catch TestException
    2
  catch _
    3
  )
""", 3

test_core """
  (try
    (throw "test")
  catch _
    ($ex .message)
  )
""", "test"

test_core """
  (try
    (throw)
    1
  catch _
    2
  finally
    3   # value is discarded
  )
""", 2

test_core """
  (try
    (throw)
    1
  catch _
    2
  finally
    (return 3)  # value is discarded
  )
""", 2

test_core """
  (try
    (throw)
    1
  catch _
    2
  finally
    (break)  # value is discarded
  )
""", 2

test_core """
  (var a 0)
  (try
    (throw)
    (a = 1)
  catch _
    (a = 2)
  finally
    (a = 3)
  )
  a
""", 3


test_core """
  (fn f _
    (throw)
    1
  catch _
    2
  finally
    3
  )
  (f)
""", 2

test_core """
  (macro m _
    (throw)
    1
  catch _
    2
  finally
    3
  )
  (m)
""", 2

test_core """
  (fn f blk
    (blk)
  )
  (f
    (->
      (throw)
      1
    catch _
      2
    finally
      3
    )
  )
""", 2

test_core """
  (do
    (throw)
    1
  catch _
    2
  finally
    3
  )
""", 2

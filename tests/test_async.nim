import unittest

import gene/types

import ./helpers

# Support asynchronous functionality
# Depending on Nim
# Support custom asynchronous call - how?
#
# Future type
# * check status
# * report progress (optionally)
# * invoke callback on finishing
# * timeout
# * exception
# * cancellation
# * await: convert to synchronous call
#

test_interpreter """
  (async 1)
""", proc(r: Value) =
  check r.kind == VkFuture

test_interpreter """
  (async (throw))   # Exception will have to be caught by await, or on_failure
  1
""", 1

test_interpreter """
  (var future (async 1))
  (var a 0)
  (future .on_success (-> (a = 1)))
  (future .on_failure (-> (a = 2)))
  a
""", 1

test_interpreter """
  (var future (async 1))
  (var a 0)
  (future .on_success (x -> (a = x)))
  a
""", 1

test_interpreter """
  (var future (async (throw)))
  (var a 0)
  (future .on_success (-> (a = 1)))
  (future .on_failure (-> (a = 2)))
  a
""", 2

test_interpreter """
  (var future (async (throw "test")))
  (var a 0)
  (future .on_failure (ex -> (a = ex)))
  (a .message)
""", "test"

# test_interpreter """
#   (var future (async (throw "test")))
#   (var a 0)
#   (future .on_success (-> (a = 1)))
#   (future .on_failure (ex -> (a = (ex .message))))
#   (for i in (range 0 100) i)  # Wait for the interpreter to check status of futures
#   a
# """, "test"

# test_interpreter """
#   (var future
#     # async will return the internal future object
#     (async (gene/sleep_async 50))
#   )
#   (var a 0)
#   (future .on_success (-> (a = 1)))
#   a   # future has not finished yet
# """, 0

# test_interpreter """
#   (var future
#     (async (gene/sleep_async 50))
#   )
#   (var a 0)
#   (future .on_success (-> (a = 1)))
#   (gene/sleep 100)
#   (for i in (range 0 100) i)  # Wait for the interpreter to check status of futures
#   a   # future should have finished
# """, 1

# test_interpreter """
#   (try
#     (await
#       (async (throw AssertionError))
#     )
#     1
#   catch AssertionError
#     2
#   catch _
#     3
#   )
# """, 2

test_interpreter """
  (await (async 1))
""", 1

test_interpreter """
  (try
    (await
      (async (throw))
    )
    1
  catch _
    2
  )
""", 2

# test_interpreter """
#   (var a)
#   (var future (gene/sleep_async 50))
#   (future .on_success (->
#     (a = 1)
#   ))
#   (await future)
#   a
# """, 1

# test_interpreter """
#   (var a "")
#   (var f1 (gene/sleep_async 50))
#   (f1 .on_success (-> (a = (a "1"))))
#   (var f2 (gene/sleep_async 200))
#   (f2 .on_success (-> (a = (a "2"))))
#   (await f1 f2)
#   a
# """, "12"

# test_interpreter """
#   (fn ^^async f _
#     1
#   )
#   (await (f))
# """, 1

# test_interpreter """
#   (fn ^^async f _
#     (throw)
#   )
#   (try
#     (await (f))
#     1
#   catch _
#     2
#   )
# """, 2

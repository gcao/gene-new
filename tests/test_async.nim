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
# Pseudo futures: futures don't run on top of os asynchroneous functionality
# e.g. async_sleep, async_read_file, async_write_file, async_http_request etc
#
# In order to make pseudo futures work, we need to have a way to let them
# run like regular futures.
# How?
# First, we should not wait for a future that will never finish - that'll be a
# programmatic error and should be caught by the interpreter. For example, if
# there is no os asynchronous stuff going on, then we should not be waiting for
# a pseudo future.
# Second, if we have to wait for a pseudo future, we probably need to create a
# timer on demand and wait for the timer to finish. While we wait for the timer,
# other code can run and resolve the pseudo future. The other code could be a
# channel callback that is invoked when message is received from the channel.
# The issue here is that other code may not be able to run because the interpreter
# is only going to call callbacks of os asynchronous stuff.

test_interpreter """
  (var future (new gene/Future))
  (future .complete 1)
  (await future)
""", 1

test_interpreter """
  (var result)
  (var future (new gene/Future))
  (future .on_success (-> (result = 1)))
  (future .on_failure (-> (result = 2)))
  (future .complete)
  (await future)
  result
""", 1

test_interpreter """
  (var result)
  (var future (new gene/Future))
  (future .on_success (-> (result = 1)))
  (future .on_failure (-> (result = 2)))
  (future .fail)
  (try
    (await future)
    (fail "should not arrive here.")
  catch *
  )
  result
""", 2

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
#   catch *
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
  catch *
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

test_interpreter """
  (fn ^^async f _
    1
  )
  (f)
""", proc(r: Value) =
  check r.kind == VkFuture

test_interpreter """
  (fn ^^async f _
    1
  )
  (await (f))
""", 1

test_interpreter """
  (fn ^^async f _
    (throw)
  )
  (try
    (await (f))
    1
  catch *
    2
  )
""", 2

test_interpreter """
  (var result 0)
  # 1000 didn't work, probably because the VM is too slow, 500 ms difference
  # is not long enough
  ((gene/sleep_async 2000).on_success(-> (result = 2000)))
  ((gene/sleep_async 500 ).on_success(-> (result = 500)))
  ($await_all)
  result
""", 2000

test_interpreter """
  (var result (new gene/Future))
  ((gene/sleep_async 1000).on_success(-> (result .complete 1)))
  (await result)
""", 1

# test_interpreter """
#   (var result false)
#   (gene/defer (result = true) 1000)
#   (gene/wait_until result) # wait, but let async code run in the middle, can take an interval and a timeout value
#   result
# """, true

# test_interpreter """
#   (var result false)
#   (gene/wait_until ^timeout 2000 result) # wait, but let async code run in the middle, can take an interval and a timeout value
#   result
# """, false

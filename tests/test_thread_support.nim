import unittest, tables

import gene/types

import ./helpers

# Multithread support:
#   $spawn
#   $spawn_wait wait for result
#   $spawn_return
#     Spawn a thread
#     Run the code in the thread
#     Return the result
#     The result is wrapped in a Future object (similar to how async works here)
#     The result can be ignored or used.
#   $thread - the current thread
#   $wait_for_threads
#     can take an optional list of threads
#     if no argument is given, wait for all threads created by myself
#     wait recursively for threads created directly or indirectly by myself
#   At the end of a thread, it should wait for all threads created by it to finish ?!
#   threads spawn threads
#   Message passing between threads
#     Messages are deeply copied on the receiving end
#     (thread .send x)
#     (thread .check_message (x -> ...))
#   In order to improve efficiency, VMs do not check messages by default.
#     It can be enabled explicitly, or enabled when a message handler is
#     registered, and can be disabled. It's the developer's responsibility
#     to make sure no message is sent to a channel if the VM doesn't handle
#     them.
#
#   Message handlers can be categorized as two types: once or multiple times

#   Re-using threads
#     may not be a good idea because it is not easy to reset the associated VM to
#     its pristine state.

# Give each thread a random id, when a thread object is re-used, the random id should
# change, so that reference to old thread can be invalidated.

test_interpreter """
  (await
    (spawn_return
      (gene/sleep 100)
      (1 + 2)
    )
  )
""", 3

test_interpreter """
  (await
    (spawn_return
      (gene/sleep 100)
      (var x
        (await
          (spawn_return
            (gene/sleep 100)
            2
          )
        )
      )
      (1 + x)
    )
  )
""", 3

test_interpreter """
  (await
    (spawn_return
      (gene/sleep 100)
      "a"
    )
  )
""", "a"

test_interpreter """
  (await
    (spawn_return
      (gene/sleep 100)
      [1 2]
    )
  )
""", new_gene_vec(1, 2)

test_interpreter """
  (await
    (spawn_return
      (gene/sleep 100)
      {^a 1 ^b 2}
    )
  )
""", {
  "a": new_gene_int(1),
  "b": new_gene_int(2),
}.toTable

test_interpreter """
  (await
    (spawn_return
      (gene/sleep 100)
      (1 ^a 2 3 4)
    )
  )
""", proc(r: Value) =
  check r.gene_type == 1
  check r.gene_props["a"] == 2
  check r.gene_children == new_gene_vec(3, 4)

test_interpreter """
  # spawn:
  # Spawn a thread
  # Run the code in the thread
  # Return the thread
  # The result of thread execution can be ignored or accessed using (thread .result)

  # All threads can send or receive messages
  # The messages are deeply copied on the receiver end.

  (var thread
    (spawn
      (loop
        ($thread .check_message (msg ->
          (if (msg == "stop")
            (break)
          )
        ))
        (gene/sleep 100)
      )
    )
  )
  (gene/sleep 100)
  (thread .send "stop")
  (thread .join)
  1
""", 1

test_interpreter """
  (spawn
    (gene/sleep 100)
    (var thread $thread/.parent)
    (thread .send 1)
  )

  (var result)
  # $thread - the current thread which is the main thread here.
  (loop
    ($thread .check_message (msg ->
      (result = msg)
      (break)
    ))
    (gene/sleep 200)
  )
  result
""", 1

test_interpreter """
  (spawn
    (gene/sleep 100)
    (var thread $thread/.parent)
    (thread .send 1)
    (thread .send 2)
    (thread .send "over")
  )

  (var result)
  # $thread - the current thread which is the main thread here.
  (loop
    ($thread .check_message (msg ->
      (if (msg == "over")
        (break)
      )
      (result = msg)
    ))
    (gene/sleep 200)
  )
  result
""", 2

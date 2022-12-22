import tables

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
#     (thread .on_message (x -> ...))

#   Re-using threads
#     may not be a good idea because it is not easy to reset the associated VM to
#     its pristine state.

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

# test_interpreter """
#   # spawn:
#   # Spawn a thread
#   # Run the code in the thread
#   # Return the thread
#   # The result of thread execution can be ignored or accessed using (thread .result)

#   # All threads can send or receive messages
#   # The messages are deeply copied on the receiver end.

#   (var thread
#     (spawn
#       (var done)
#       (var result)
#       ($thread .on_message
#         (msg ->
#           (done = true)
#           (result = msg)
#         )
#       )
#       (while (not done)
#         # Add 10 noops to make sure futures are checked in every iteration
#         (noop) (noop) (noop) (noop) (noop) (noop) (noop) (noop) (noop) (noop)
#         (gene/sleep 100)
#       )
#       result
#     )
#   )
#   (thread .send 1)
#   (await (thread .result))
# """, 1

# test_interpreter """
#   (spawn
#     (gene/sleep 100)
#     (var thread (gene/thread/main))
#     (thread .send 1)
#   )

#   (var result)
#   # $thread - the current thread which is the main thread here.
#   ($thread .on_message
#     (msg -> (result = msg))
#   )
#   ($wait_for_threads) # Wait for running threads to finish
#   result
# """, 1

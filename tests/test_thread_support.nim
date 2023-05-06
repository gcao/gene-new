import unittest, tables

import gene/types

import ./helpers

# Multithread support:
#   A VM should know whether there is any child thread spawned from itself
#   A VM should wait for all child threads automatically. A custom method
#     should be implemented instead of using the standard joinThread method
#     because it'll block the current thread.
#   If a VM has child threads, it should check for messages every X evaluations
#     (allow this to be disabled)
#   Child threads can talk to each other. It's the developer's responsibility to
#     figure out the thread & channel to send message to.
#   Any read/write of the shared thread metadata should be guarded by a lock.
#   Allow sending more code to a running thread (the receiving thread should
#     not have ended.)
#   Allow arguments to be passed when running code inside a thread (args will be
#     deeply copied)

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
#   Message handlers can be deregistered when it is not needed any more.
#
#   Message and reply
#     Can be used to simulate real time communication
#     Each messaage can be given a unique id
#     A reply can be sent for any given message (no multi replies are allowed)
#     Reply will know exactly which channel to use
#     The sender can select to wait for reply or register a callback for the reply
#     Replies are not handled by regular message handlers
#     The order of replies/messages are not guaranteed
#
#     A reply can be sent for another reply (the sender has to add a flag to
#       signify the receiver that a reply is expected.) - bad idea!
#
#     Maybe we can allow multiple unrelated messages to be sent in one shot in
#       order to improve efficiency?!
#
#   Broadcasting
#     Should limit to my child threads, or subset of my child threads

#   Re-using threads
#     may not be a good idea because it is not easy to reset the associated VM to
#     its pristine state.

# Give each thread a random id, when a thread object is re-used, the random id should
# change, so that reference to old thread can be invalidated.

# Design of a multithreading HTTP server
#   The main thread listens on the socket for incoming request
#   For each incoming request
#     Parse request
#     A worker thread is spawned (can be done while the main thread is idling)
#     Send message to the worker thread to process the request
#     Wait for reply
#     Stop the worker thread (can be done while the main thread is idling)
#     Send reply to the client
#   Global states and user sessions should be stored in DB
#
#   This is not very efficient because the worker threads are not reused and it's
#     expensive to start/stop a worker thread.
#   If we reuse worker threads, some requests may change the global environment by
#     accident. This will cause hard-to-catch bugs.
#   We probably should let the developer decide whether a thread should be reused.

test_interpreter """
  (await
    (spawn_return
      (gene/sleep 100)
      (1 + 2)
    )
  )
""", 3

# test_interpreter """
#   (await
#     (spawn_return ^args {^first 1 ^second 2}
#       (gene/sleep 100)
#       (first + second)
#     )
#   )
# """, 3

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
      (_ ^a 2 3 4)
    )
  )
""", proc(r: Value) =
  check r.gene_props["a"] == 2
  check r.gene_children == new_gene_vec(3, 4)

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
#       (var done false)
#       ($thread .on_message (msg ->
#         (if (msg == "stop")
#           (done = true)
#           true # tell the interpreter that the message is handled, do not pass the message to next callback
#         )
#       ))
#       (while (not done)
#         (gene/sleep 100)
#       )
#     )
#   )
#   (gene/sleep 100)
#   (thread .send "stop")
#   (thread .join)
#   1
# """, 1

# test_interpreter """
#   (spawn
#     (gene/sleep 100)
#     (var thread $thread/.parent)
#     (thread .send 1)
#   )

#   (var result (new gene/Future))

#   # $thread - the current thread which is the main thread here.
#   ($thread .on_message (msg ->
#     (result .complete msg)
#     true
#   ))

#   (await result)
# """, 1

# test_interpreter """
#   (spawn
#     (gene/sleep 100)
#     (var thread $thread/.parent)
#     (thread .send 1)
#     (thread .send 2)
#     (thread .send "over")
#   )

#   (var result)

#   ($thread .on_message (msg ->
#     (if (msg == "over")
#       (break)
#     )
#     (result = msg)
#   ))

#   result
# """, 2

# test_interpreter """
#   (var thread
#     (spawn ^args {^x 100}
#       (var global/finished false)
#       (while (not global/finished)
#         (gene/sleep x)
#       )
#     )
#   )
#   (gene/sleep 200)
#   (thread .run ^args {^x true}
#     (global/finished = x)
#   )
#   (thread .join)
#   1
# """, 1

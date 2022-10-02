import unittest

import gene/types
import gene/interpreter

import ./helpers

# A built-in pub-sub API can be created that works similarly to this.

# Initialize a stream
# Register callbacks on new data
# When a callback is registered, a unique handle is returned
# Same callback can be registered multiple times, different handle is returned each time
# Callbacks can be deregistered using the handle
# Close stream
# Callbacks are deregistered automatically

# Callback function signature:
# (fnx [item, index]) - result is ignored

# Data are pushed to the stream sequentially
# Callbacks are called in the order that they are registered
# Stream don't hold data
# Stream don't keep track of which data is sent to which callback
# Stream won't wait till the callback finishes its work. What if the callback is synchronous?

# Each item is assigned a 1-based index
# The callback is invoked with the data item and its index. It can choose to use
#   both or either or none of those two parameters.
# The callback can return anything but it will be ignored by the publisher.
# [Optional] When a callback is registered, an optional range can be used to determine when
#   the callback should kick in and when it should be de-registered.

# Synchronous vs asynchronous callbacks
# Allow the client to tell us whether the callback is an asynchronous callback
# If it is, we don't have to start it in a new thread to make it asynchronous/non-blocking
# This may cause problem if the callback is still blocking

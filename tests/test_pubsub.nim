import unittest

import gene/types
import gene/interpreter

import ./helpers

# The goal of this feature / module is to serve as a reference implementation
# for common functionalities seen in a registry, plus additional things I like.

# If an application needs something not implemented in the standard registry,
# it's recommended to create its own registry implementation.

# Pub/sub system concepts
# Dispatcher   - a central system that is known to all publishers and subscribers,
#              where messages are routed.
# Message      - entities passed between publishers and subscribers.
# Message type - identifiers used to distinguish different messages.
# Publisher    - the sending end of messages
# Subscriber   - the receiving end of messages
# publish
# subscribe

# An event can trigger more events. This is called event cascading effect.

test_interpreter """
  (var registry (new genex/Registry))
  (registry .register "x" 1)
  (registry .request "x")
""", 1

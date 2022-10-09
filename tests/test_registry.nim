import unittest

import gene/types
import gene/interpreter

import ./helpers

# See https://github.com/gcao/free_mart.js/blob/master/public/javascripts/spec/free_mart_spec.coffee
# for ideas

# Q: Can we combine producer/consumer and pub/sub in one solution?
# A: Not a good idea. The two patterns handles different use cases even though
#    they look somewhat similar.

# The goal of this feature / module is to serve as a reference implementation
# for common functionalities seen in a registry, plus additional things I like.

# If an application needs something not implemented in the standard registry,
# it's recommended to create its own registry implementation.

# Producer/consumer system concepts:
# Registry - a central place that is known to all producers and consumers, in
#            which resources are stored.
# Resource - entities produced by producer and stored in the registry at a given
#            location.
#            resources can be produced on demand, e.g. a report created on demand
#            from a consumer.
#            resources can be transient or permanent.
#            transient resources are gone after being consumed one or x times.
#            permanent resources are always available unless the producers
#            take them off from the registry.
# Location - an addressable location inside the registry.
#            location and its address are interchangeable term.
#            location can be static or dynamic.
#            static locations: /index.html
#            dynamic locations: /users/?/profile.html
# Producer - something that produces resources, e.g. a database
# Consumer - something that consumes resources, e.g. a front end for a database
# register - the action that a producer puts a resource at a location, or tells
#            the registry what to do when a resource at some location is
#            requested. The resource can be lazily created on request.
# request  - the action that a consumer asks for a resource at a given location.

# A resource can depend on other resources. They can be explicitly listed on
# registration. A dependency tree can be generated.

# State machine concepts
# State
# Action/event + input
# Transition (change from one state to another)
# Start state
# End state(s)

# Similarities and differences between producer/consumer and pub/sub systems.

# Similarities:
# Registry - Dispatcher
# Resource - Message
# Location - Message type
# Producer - publisher
# Consumer - Subscriber

# Differences:
# In producer/consumer system, the consumer is the one that triggers chain of
# reaction.
# In pub/sub system, the publisher is the one that triggers chain of reaction.

# In producer/consumer, the registry holds resources.
# In pub/sub system, the dispatcher routes messages.

# Location can be static or dynamic.
# Message type should be static, however the subscriber can subscribe to multiple
# types of messages.

# The registering action should not block. However the requesting action can block
# or be asynchronous.
# The publishing and subscribing action should never block.

# Resources can be transient or long-living.
# Messages are transient.

test_interpreter """
  (var registry (new genex/Registry))
  (registry .register "x" 1)
  (registry .request "x")
""", 1

test_interpreter """
  (var registry (new genex/Registry))
  (var result)
  ((registry .req_async "x")
    .on_success (value ->
      (result = value)
    )
  )
  (registry .register "x" 1)
  ($await_all)
  result
""", 1

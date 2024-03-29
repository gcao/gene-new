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
#            location, path and address are interchangeable term.
#            location should be static but a request can include additional
#            parameters which is used to generate a resource.
#            locations: /index.html
#            locations that are dynamic-ish: /users/:user_id/profile.html
#            it'll be up to the user of the registry to design the location
#            scheme.
# Middleware - some program that can perform some action when a request is
#            received.
# Producer - something that produces resources, e.g. a database
# Consumer - something that consumes resources, e.g. a front end for a database
# register - the action that a producer puts a resource at a location, or tells
#            the registry what to do when a resource at some location is
#            requested. The resource can be lazily created on request.
# request  - the action that a consumer asks for a resource at a given location.

# Middleware design
# A registry-wide list of middlewares are stored.
# Each middleware takes a list of paths or path patterns and an action.
# Middleware type: before/after/around
# BEFORE middleware: can exit prematurely(by throwing a special error?)
# AFTER  middleware: can alter result etc.
# AROUND middleware: can do everything BEFORE/AFTER supports plus more.

# Middleware list is a static list. No items can be removed after an item is
# added. However an item can be replaced with nil when it's not needed any more.
# Middleware is aware of its own position and can tell the registry to go to the
# next one or exit prematurely.

# When a request is made, if a list of middleware is available, middlewares
# applicable to the request are stored in a path<=>middlewares mapping cache and
# applied in the order.
# When a new middleware is defined, all existing mappings are validated and
# cleared if necessary.

# A registry can work without a producer and let middlewares do all the magic.

# not_found_callbacks: one or multiple not_found event handlers can be registered.
# If one handler generates a resource, other handlers are skipped.

# A resource can depend on other resources. Dependencies can be explicitly listed
# on registration. A dependency tree can be generated using this information.

# State machine concepts
# State
# Action/event + input
# Transition (change from one state to another)
# Start state
# End state(s)

# Similarities and differences between producer/consumer and pub/sub systems.

# Similarities:
# Registry   - Dispatcher
# Resource   - Message
# Location   - Message type
# Middleware - ???
# Producer   - publisher
# Consumer   - Subscriber

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
  (var registry (new genex/Registry "test"))
  registry/.name
""", "test"

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

test_interpreter """
  # <BEFORE> middleware should work
  (var registry (new genex/Registry))
  (var a 1)
  (registry .register "x" 100)
  (registry .before "x"
    ([middleware req] -> (a += 10))
  )
  (registry .request "x")
  a
""", 11

test_interpreter """
  # <AROUND> middleware should work
  (var registry (new genex/Registry))
  (registry .register "x" 1)
  # Add a middleware that runs after a resource is obtained.
  (registry .around "x"
    ([middleware req] ->
      ((middleware .call_next req) + 10)
    )
  )
  (registry .request "x")
""", 11

test_interpreter """
  # <AFTER> middleware should work
  (var registry (new genex/Registry))
  (registry .register "x" 1)
  # Add a middleware that runs after a resource is obtained.
  (registry .after "x"
    ([middleware req res] -> (res .set_value (res/.value + 10)))
  )
  (registry .request "x")
""", 11

test_interpreter """
  # producer that uses a callback should work
  (var registry (new genex/Registry))
  (registry .register_callback "x"
    ([registry req] ->
      (req/.args/0 + 10)
    )
  )
  (registry .request "x" 1)
""", 11

test_interpreter """
  (var registry (new genex/Registry))
  (registry .register #/x/ 1)
  (registry .request "x")
""", 1

test_interpreter """
  # Exact path takes precedence over pattern
  (var registry (new genex/Registry))
  (registry .register "x" 1)
  (registry .register #/x/ 2)
  (registry .request "x")
""", 1

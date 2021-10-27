import gene/types

import ./helpers

# $include
#
# Work like source code is copied and wrapped with "do", i.e. (do <included source>)
# Search like modules, no need to specify absolute path
# path <=> code mappings can be defined so that we don't need to depend on the file system
#
# Pros:
#   Can be used to remove some boilerplate (e.g. imports)
# Cons:
#   More indirection, code becomes harder to understand

test_interpreter """
  ($include "tests/fixtures/include_example")
  a
""", 100

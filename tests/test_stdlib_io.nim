import gene/types

import ./helpers

test_core """
  (gene/File/read "tests/fixtures/test.txt")
""", "line1\nline2"

test_core """
  (var file "/tmp/test.txt")
  (gene/File/write file "test")
  (gene/File/read file)
""", "test"

test_core """
  (var file (gene/File/open "tests/fixtures/test.txt"))
  (file .read)
""", "line1\nline2"

# TODO: file should be a file object
# test_core """
#   (var f "tests/fixtures/file.gene")
#   (import file from f)
#   (assert (file == f))
# """

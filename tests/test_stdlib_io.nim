import gene/types

import ./helpers

test_interpreter """
  (gene/File/read "tests/fixtures/test.txt")
""", "line1\nline2"

test_interpreter """
  (var file "/tmp/test.txt")
  (gene/File/write file "test")
  (gene/File/read file)
""", "test"

# test_interpreter """
#   (var file (gene/File/open "tests/fixtures/test.txt"))
#   (file .read)
# """, "line1\nline2"

# TODO: file should be a file object
# test_interpreter """
#   (var f "tests/fixtures/file.gene")
#   (import file from f)
#   (assert (file == f))
# """

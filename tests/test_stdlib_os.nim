import os, osproc

import gene/types

import ./helpers

test_interpreter """
  ($env "HOME")
""", get_env("HOME")

test_interpreter """
  ($env "XXXX" "Not found")
""", "Not found"

test_interpreter """
  ($set_env "XXXX" "test")
  ($env "XXXX" "Not found")
""", "test"

test_interpreter """
  (gene/os/exec "pwd")
""", execCmdEx("pwd")[0]

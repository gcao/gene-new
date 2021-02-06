import os, osproc

import gene/types

import ./helpers

test_core """
  (env "HOME")
""", get_env("HOME")

test_core """
  (env "XXXX" "Not found")
""", "Not found"

test_core """
  (gene/os/exec "pwd")
""", execCmdEx("pwd")[0]

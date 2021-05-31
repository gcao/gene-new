# Package

version       = "0.1.0"
author        = "Guoliang Cao"
description   = "Gene - a general purpose language"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["gene"]

# Dependencies

requires "nim >= 1.0.0"

task buildext, "Build the Nim extension":
  exec "nim c --app:lib --outdir:build src/genex/http.nim"
  exec "nim c --app:lib --outdir:tests tests/extension.nim"

# before test:
#   exec "nim c --app:lib --outdir:tests tests/extension.nim"

task test, "Runs the test suite":
  exec "nim c -r tests/test_interpreter.nim"
  exec "nim c -r tests/test_fp.nim"
  exec "nim c -r tests/test_namespace.nim"
  exec "nim c -r tests/test_oop.nim"

# Package

version       = "0.1.0"
author        = "Guoliang Cao"
description   = "Gene - a general purpose language"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
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
  requires "build"
  exec "nim c -r tests/test_parser.nim"
  exec "nim c -r tests/test_interpreter.nim"
  exec "nim c -r tests/test_scope.nim"
  exec "nim c -r tests/test_interpreter_symbol.nim"
  exec "nim c -r tests/test_interpreter_repeat.nim"
  exec "nim c -r tests/test_interpreter_for.nim"
  exec "nim c -r tests/test_enum.nim"
  exec "nim c -r tests/test_exception.nim"
  exec "nim c -r tests/test_fp.nim"
  exec "nim c -r tests/test_namespace.nim"
  exec "nim c -r tests/test_oop.nim"
  exec "nim c -r tests/test_cast.nim"
  exec "nim c -r tests/test_pattern_matching.nim"
  exec "nim c -r tests/test_macro.nim"
  exec "nim c -r tests/test_block.nim"
  exec "nim c -r tests/test_async.nim"
  exec "nim c -r tests/test_module.nim"
  exec "nim c -r tests/test_selector.nim"
  exec "nim c -r tests/test_template.nim"
  exec "nim c -r tests/test_native.nim"

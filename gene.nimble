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
  exec "nim c --app:lib -d:useMalloc --outdir:build src/genex/http.nim"
  exec "nim c --app:lib -d:useMalloc --outdir:build src/genex/sqlite.nim"

after build:
  exec "nimble buildext"

before test:
  exec "nim c --app:lib -d:useMalloc --outdir:tests tests/extension.nim"
  exec "nim c --app:lib -d:useMalloc --outdir:tests tests/extension2.nim"
  exec "nim c --app:lib -d:useMalloc --outdir:example-projects/my-lib/src example-projects/my-lib/src/my_lib/index.nim"

task test, "Runs the test suite":
  exec "nim c -r tests/test_parser.nim"
  exec "nim c -r tests/test_interpreter.nim"
  exec "nim c -r tests/test_scope.nim"
  exec "nim c -r tests/test_interpreter_symbol.nim"
  exec "nim c -r tests/test_interpreter_repeat.nim"
  exec "nim c -r tests/test_interpreter_for.nim"
  exec "nim c -r tests/test_interpreter_case.nim"
  exec "nim c -r tests/test_enum.nim"
  exec "nim c -r tests/test_arithmetic.nim"
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
  # exec "nim c -r tests/test_package.nim"
  exec "nim c -r tests/test_selector.nim"
  exec "nim c -r tests/test_template.nim"
  exec "nim c -r tests/test_native.nim"
  exec "nim c -r tests/test_ext.nim"
  exec "nim c -r tests/test_metaprogramming.nim"

  exec "nim c -r tests/test_stdlib.nim"
  exec "nim c -r tests/test_stdlib_class.nim"
  exec "nim c -r tests/test_stdlib_string.nim"
  exec "nim c -r tests/test_stdlib_class.nim"
  exec "nim c -r tests/test_stdlib_array.nim"
  exec "nim c -r tests/test_stdlib_map.nim"
  exec "nim c -r tests/test_stdlib_gene.nim"
  exec "nim c -r tests/test_stdlib_regex.nim"
  exec "nim c -r tests/test_stdlib_io.nim"
  exec "nim c -r tests/test_stdlib_datetime.nim"
  exec "nim c -r tests/test_stdlib_os.nim"
  exec "nim c -r tests/test_stdlib_json.nim"

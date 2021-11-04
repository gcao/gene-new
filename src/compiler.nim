import os

import ./gene/types

# https://github.com/gcao/gene-new/issues/6

# nim c -r src/compiler.nim any.gene build/any.nim
# nim -p:src c -r build/any.nim

# return file path for generated file
proc generate_nim_file(src_file, dst_file: string): string =
  echo "Generate .nim file for " & src_file
  var f = open(dst_file, fm_write)
  f.write_line("# This is a generated file!!!\n")
  f.write_line("import gene/types")
  f.write_line("import gene/parser")
  f.write_line("import gene/interpreter")
  f.write_line("init_app_and_vm()")
  f.write_line("var source = \"\"\"")
  f.write_line(read_file(src_file))
  f.write_line("\"\"\"")
  f.write_line("discard VM.eval(source)")
  echo "Done. The generated file is " & dst_file

proc main() =
  var args = command_line_params()
  var src_file: string
  if args.len > 0:
    src_file = args[0]
  else:
    src_file = ""

  var dst_file: string
  if args.len > 1:
    dst_file = args[1]
  else:
    dst_file = "output.nim"

  echo generate_nim_file(src_file, dst_file)

when isMainModule:
  main()

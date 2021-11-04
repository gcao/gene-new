import os

import ./gene/types

# https://github.com/gcao/gene-new/issues/6

# Generate .nim file
# nim c -r src/compiler.nim any.gene build/any.nim
# gene compile any.gene build/any.nim

# Compile and run .nim file
# nim -p:src c -r build/any.nim

# Compile .nim file
# nim -p:src c --out:build/any build/any.nim

# Run executable
# build/any

# return file path for generated file
proc generate_nim_file*(src_file: string, dst_file = "build/output.nim") =
  echo "Generate .nim file for " & src_file
  var f = open(dst_file, fm_write)
  f.write_line("# This is a generated file!!!\n")
  f.write_line("import gene/types")
  f.write_line("import gene/parser")
  f.write_line("import gene/interpreter")
  f.write_line("init_app_and_vm()")
  f.write_line("VM.init_package(\".\")")
  f.write_line("var source = \"\"\"")
  f.write_line(read_file(src_file))
  f.write_line("\"\"\"")
  f.write_line("discard VM.run_file(\"" & src_file & "\", source)")
  f.write_line("VM.wait_for_futures()")
  echo "Done. The generated file is " & dst_file

proc main() =
  var args = command_line_params()
  var src_file: string
  if args.len > 0:
    src_file = args[0]
  else:
    echo "Usage: gene compile ???.gene [???.nim]"
    quit(0)

  if args.len > 1:
    generate_nim_file(src_file, args[1])
  else:
    generate_nim_file(src_file)

when isMainModule:
  main()

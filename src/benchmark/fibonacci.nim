when isMainModule:
  import times

  import ./gene/types
  import ./gene/parser
  import ./gene/interpreter

  init_app_and_vm()

  var code = """
    (fn fib n
      (if (n < 2)
        n
      else
        ((fib (n - 1)) + (fib (n - 2)))
      )
    )
    (fib 24)
  """

  var p = new_parser()
  var e = translate(p.read_all(code))
  let module = new_module(VM.app.pkg)
  VM.app.main_module = module
  var frame = Frame(ns: module.ns, scope: new_scope())
  let start = cpuTime()
  let result = eval(frame, e)
  echo "Time: " & $(cpuTime() - start)
  echo "fib(24) = " & $result

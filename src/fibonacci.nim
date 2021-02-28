when isMainModule:
  import times

  import ./gene/types
  import ./gene/translators
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
  let e = translate(VM.prepare(code))
  let module = new_module()
  var frame = new_frame()
  frame.d.ns = module.root_ns
  frame.d.scope = new_scope()
  let start = cpuTime()
  let result = VM.eval(frame, e)
  echo "Time: " & $(cpuTime() - start)
  echo "fib(24) = " & $result

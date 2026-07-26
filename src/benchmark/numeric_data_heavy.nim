# import times

import ./gene/types
import ./gene/interpreter

init_app_and_vm()

proc use_generic_array(self: VirtualMachine) =
  discard self.eval """
    (var arr [
      [1 2 3 4 5 6 7 8 9 10]
      [1 2 3 4 5 6 7 8 9 10]
      [1 2 3 4 5 6 7 8 9 10]
      [1 2 3 4 5 6 7 8 9 10]
      [1 2 3 4 5 6 7 8 9 10]
      [1 2 3 4 5 6 7 8 9 10]
      [1 2 3 4 5 6 7 8 9 10]
      [1 2 3 4 5 6 7 8 9 10]
      [1 2 3 4 5 6 7 8 9 10]
      [1 2 3 4 5 6 7 8 9 10]
    ])
    # TODO: multiply with itself
  """

proc use_special_array(self: VirtualMachine) =
  discard self.eval """
    (var arr (#IntArray2
      1 2 3 4 5 6 7 8 9 10
      1 2 3 4 5 6 7 8 9 10
      1 2 3 4 5 6 7 8 9 10
      1 2 3 4 5 6 7 8 9 10
      1 2 3 4 5 6 7 8 9 10
      1 2 3 4 5 6 7 8 9 10
      1 2 3 4 5 6 7 8 9 10
      1 2 3 4 5 6 7 8 9 10
      1 2 3 4 5 6 7 8 9 10
      1 2 3 4 5 6 7 8 9 10
    ))
    (var arr2 (arr .mul arr))
  """

VM.use_generic_array()
VM.use_special_array()

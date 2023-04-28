import gene/types

import ./helpers

test_interpreter """
  (class A
    (.fn init _
      (/data = [0])
    )
    (.fn get_child i
      (/data ./ i)
    )
  )
  (var a (new A))
  a/0
""", 0

test_interpreter """
  (class A
    (.fn init _
      (/data = [0])
    )
    (.fn get_child i
      (/data ./ i)
    )
    (.fn set_child [i value]
      ($set /data i value)
      value
    )
  )
  (var a (new A))
  (a/0 = 1)
  a/0
""", 1

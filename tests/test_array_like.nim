import gene/types

import ./helpers

test_interpreter """
  (class A
    (method init _
      (/data = [0])
    )
    (method get_child i
      (/data ./ i)
    )
  )
  (var a (new A))
  a/0
""", 0

test_interpreter """
  (class A
    (method init _
      (/data = [0])
    )
    (method get_child i
      (/data ./ i)
    )
    (method set_child [i value]
      ($set /data i value)
      value
    )
  )
  (var a (new A))
  (a/0 = 1)
  a/0
""", 1

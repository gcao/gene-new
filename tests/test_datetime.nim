import unittest, times

import gene/types

import ./helpers

#
# Date
# DateTime
# Time
# Timezone
# gene/now
# gene/today, gene/yesterday, gene/tomorrow
#

test_core """
  ((gene/today) .year)
""", now().year

test_core """
  ((gene/now) .year)
""", now().year

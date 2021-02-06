import os, sequtils

import ./map_key
import ./types

# Some logics can not be put in interpreter.nim because the compiler complains

proc init_extras*(self: VirtualMachine) =
  var cmd_args = command_line_params().map(str_to_gene)
  self.app.ns[CMD_ARGS_KEY] = cmd_args

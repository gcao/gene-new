import tables

import ../types
import ../map_key
import ../translators

type
  ExDependency* = ref object of Expr
    name*: MapKey
    version*: string

proc eval_dep(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  todo()
  # Locate app's root dir

  # Search dependencies installed for app     (<APP DIR>/packages)
  # Search dependencies installed for user    ($HOME/.gene/packages)
  # Search dependencies installed for runtime ($GENE_HOME/packages)

  # Use installed compatible version that is already installed
  # If not installed, install latest version that is compatible

  # If app's package is adhoc, install to $HOME/.gene/packages
  # Else, install to <APP DIR>/packages

  # Do the same for nested dependencies

proc translate_dep(value: Value): Expr =
  var e = ExDependency(
    evaluator: eval_dep,
    name: value.gene_data[0].str.to_key,
  )
  if value.gene_data.len > 1:
    e.version = value.gene_data[1].str
  return e

proc init*() =
  GeneTranslators["$dep"] = translate_dep

import tables

import ../types
import ../map_key
import ../translators
import ../interpreter

type
  Dependency* = ref object
    name*: string
    version*: string
    location*: string

  DependencyRoot* = ref object
    package*: Package
    map*: Table[string, seq[Dependency]]
    children*: Table[string, DependencyNode]

  DependencyNode* = ref object
    root*: DependencyRoot
    data*: Dependency
    children*: Table[string, DependencyNode]

  ExDependency* = ref object of Expr
    name*: Expr
    version*: Expr
    location*: Expr

proc build_dep_tree(self: Package, root: DependencyRoot) =
  todo()

proc build_dep_tree(self: Package) =
  var root = DependencyRoot()
  root.package = self
  self.build_dep_tree(root)

proc eval_dep(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExDependency](expr)
  var name = self.eval(frame, expr.name)
  var version = ""
  if expr.version != nil:
    version = self.eval(frame, expr.version).str
  var pkg = frame.ns["$pkg"]
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
    name: translate(value.gene_data[0]),
  )
  if value.gene_data.len > 1:
    e.version = translate(value.gene_data[1])
  if value.gene_props.has_key("location".to_key):
    e.location = translate(value.gene_props["location"])
  return e

proc init*() =
  GeneTranslators["$dep"] = translate_dep

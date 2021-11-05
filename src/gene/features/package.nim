import sequtils, tables

import ../types
import ../map_key
import ../translators
import ../interpreter

type
  ExDependency* = ref object of Expr
    name*: Expr
    version*: Expr
    path*: Expr
    repo*: Expr
    commit*: Expr # applicable if repo is given

proc eval_dep(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExDependency](expr)
  var name = self.eval(frame, expr.name).str
  var version = ""
  if expr.version != nil:
    version = self.eval(frame, expr.version).str
  var dep = Dependency(
    name: name,
    version: version,
  )
  if expr.path != nil:
    dep.type = "path"
    dep.path = self.eval(frame, expr.path).str

  var pkg = frame.ns["$pkg"].pkg
  pkg.dependencies[name] = dep
  var node = DependencyNode(root: APP.dep_root)
  dep.build_dep_tree(node)

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
  if value.gene_props.has_key("path".to_key):
    e.path = translate(value.gene_props["path"])
  return e

proc init*() =
  GeneTranslators["$dep"] = translate_dep

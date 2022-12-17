import ../types
import ../parser
import ../interpreter_base

type
  ExInclude* = ref object of Expr
    path*: Expr
    # pkg*: Expr

proc eval_include(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExInclude](expr)
  var dir = "" # TODO: logic similar to module paths
  var path = self.eval(frame, expr.path).str
  var code = read_file(dir & path & ".gene")
  var parsed = read_all(code)
  var e = translate(parsed)
  self.eval(frame, e)

proc translate_include(value: Value): Expr {.gcsafe.} =
  result = ExInclude(
    evaluator: eval_include,
    path: translate(value.gene_children[0]),
  )

proc init*() =
  VmCreatedCallbacks.add proc(self: var VirtualMachine) =
    self.global_ns.ns["$include"] = new_gene_processor(translate_include)

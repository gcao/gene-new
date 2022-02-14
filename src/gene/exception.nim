import macros

import ./types

type
  ExException* = ref object of Expr
    ex*: ref system.Exception

proc eval_exception(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  # raise cast[ExException](expr).ex
  not_allowed("eval_exception")

proc new_ex_exception*(ex: ref system.Exception): ExException =
  ExException(
    evaluator: eval_exception, # Should never be called
    ex: ex,
  )

macro wrap_exception*(p: untyped): untyped =
  if p.kind == nnkProcDef:
    var convert: string
    var ret_type = $p[3][0]
    case ret_type:
    of "Value":
      convert = "exception_to_value"
    of "Expr":
      convert = "new_ex_exception"
    else:
      todo("wrap_exception does NOT support returning type of " & ret_type)

    p[6] = nnkTryStmt.newTree(
      p[6],
      nnkExceptBranch.newTree(
        infix(newDotExpr(ident"system", ident"Exception"), "as", ident"ex"),
        nnkReturnStmt.newTree(
          nnkCall.newTree(ident(convert), ident"ex"),
        ),
      ),
    )
    return p
  else:
    todo("ex2val " & $nnkProcDef)

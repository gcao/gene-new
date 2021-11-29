include gene/extension/boilerplate

type
  Clause = ref object of RootObj

  TableLike = ref object of Clause
    alias: string

  Table = ref object of TableLike
    name: string

  # PseudoTable = ref object of TableLike
  #   stmt: Select

  JoinKind = enum
    JkDefault
    # JkLeft
    # JkRight
    # JkInner
    # JkOuter

  Join = ref object of Clause
    table: TableLike
    kind: JoinKind
    conditions: seq[Condition]

  ColumnLike = ref object of Clause
    alias: string

  Column = ref object of ColumnLike
    table_name: string
    name: string

  # PseudoColumn = ref object of ColumnLike
  #   clause: Clause # not all clause can work like a column

  Literal = ref object of ColumnLike
    value: Value

  Condition = ref object of Clause

  BinOp = enum
    BinAnd

  BinClause = ref object of ColumnLike
    op: BinOp
    left, right: Clause

  # Call = ref object of Clause
  #   name: string
  #   args: seq[Clause]

  Statement = ref object of Clause

  Select = ref object of Statement
    tables: seq[TableLike]
    joins: seq[Join]
    cols: seq[ColumnLike]
    conditions: seq[Condition]

  ExSelect = ref object of Expr

proc eval_select(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExSelect](expr)
  # self.eval(frame, expr.data)
  todo()

proc translate_select(value: Value): Expr {.wrap_exception.} =
  return ExSelect(
    evaluator: eval_wrap(eval_select),
  )

{.push dynlib exportc.}

proc init*(): Value {.wrap_exception.} =
  result = new_namespace("sqlite")
  GENEX_NS.ns["sqlite"] = result

  result.ns["select"] = new_gene_processor(translate_select)

{.pop.}

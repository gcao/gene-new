import db_sqlite

include gene/extension/boilerplate

type
  CustomConnection = ref object of CustomValue
    conn: DbConn

  CustomStatement = ref object of CustomValue
    stmt: Statement

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

  Star = ref object of ColumnLike
    table_name: string

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

  # ExSelect = ref object of Expr
  #   data: Expr

  SelectState = enum
    SlSelect
    SlColumn
    SlFrom
    SlTable
    SlWhere
    SlCondition

# var SELECT = new_gene_symbol("select")

var ConnectionClass: Value
var StatementClass: Value

# method to_s(self: Clause): string {.base.} =
#   todo("Clause.to_s")

# method to_s(self: Statement): string =
#   todo("Statement.to_s")

# method to_s(self: Select): string =
#   todo("Select.to_s")

# proc to_column(value: Value): ColumnLike =
#   todo("to_column")

# proc to_select(value: Value): Select =
#   result = Select()
#   var state = SlSelect
#   for item in value.gene_data:
#     case state:
#     of SlSelect:
#       if item == FROM:
#         not_allowed("to_select " & $value)
#     else:
#       todo("to_select " & $state)

# proc to_statement(value: Value): Statement =
#   if value.gene_type == SELECT:
#     return to_select(value)
#   else:
#     todo("to_statement " & $value)

# proc eval_select(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value {.wrap_exception.} =
#   var expr = cast[ExSelect](expr)
#   var output = self.eval(frame, expr.data)
#   var stmt = to_select(output)
#   new_gene_custom(CustomStatement(stmt: stmt), StatementClass.class)

# proc translate_select(value: Value): Expr {.wrap_exception.} =
#   var e = ExSelect(
#     evaluator: eval_wrap(eval_select),
#   )
#   var tmpl = new_gene_gene(new_gene_symbol("$render"))
#   tmpl.gene_data.add(value)
#   e.data = translate(tmpl)
#   return e

proc open*(args: Value): Value {.wrap_exception.} =
  var db = open(args.gene_data[0].str, "", "", "")
  new_gene_custom(CustomConnection(conn: db), ConnectionClass.class)

proc exec*(self: Value, args: Value): Value {.wrap_exception.} =
  result = new_gene_vec()
  var conn = cast[CustomConnection](self.custom).conn
  var stmt: string
  var arg0 = args.gene_data[0]
  case arg0.kind
  of VkString:
    stmt = arg0.str
  # of VkCustom:
  #   if arg0.custom_class == StatementClass.class:
  #     stmt = cast[Statement](arg0.custom).to_s
  #   else:
  #     todo("Connection.exec " & $arg0.custom_class.name)
  else:
    todo("Connection.exec " & $arg0.kind)
  for row in conn.instant_rows(sql(stmt)):
    var item = new_gene_vec()
    for i in 0..row.len():
      item.vec.add(row[i])
    result.vec.add(item)

proc close*(self: Value, args: Value): Value {.wrap_exception.} =
  cast[CustomConnection](self.custom).conn.close()

{.push dynlib exportc.}

proc init*(): Value {.wrap_exception.} =
  result = new_namespace("sqlite")
  GENEX_NS.ns["sqlite"] = result

  # result.ns["select"] = new_gene_processor(translate_select)
  result.ns["open"] = NativeFn(open)

  ConnectionClass = new_gene_class("Connection")
  result.ns["Connection"] = ConnectionClass
  ConnectionClass.def_native_method("close", method_wrap(close))
  ConnectionClass.def_native_method("exec", method_wrap(exec))

  StatementClass = new_gene_class("Statement")
  result.ns["Statement"] = StatementClass
{.pop.}

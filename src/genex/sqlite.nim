import db_sqlite

include gene/extension/boilerplate

type
  Connection = ref object of CustomValue
    conn: DbConn

  # Clause = ref object of RootObj

  # TableLike = ref object of Clause
  #   alias: string

  # Table = ref object of TableLike
  #   name: string

  # # PseudoTable = ref object of TableLike
  # #   stmt: Select

  # JoinKind = enum
  #   JkDefault
  #   # JkLeft
  #   # JkRight
  #   # JkInner
  #   # JkOuter

  # Join = ref object of Clause
  #   table: TableLike
  #   kind: JoinKind
  #   conditions: seq[Condition]

  # ColumnLike = ref object of Clause
  #   alias: string

  # Column = ref object of ColumnLike
  #   table_name: string
  #   name: string

  # # PseudoColumn = ref object of ColumnLike
  # #   clause: Clause # not all clause can work like a column

  # Literal = ref object of ColumnLike
  #   value: Value

  # Condition = ref object of Clause

  # BinOp = enum
  #   BinAnd

  # BinClause = ref object of ColumnLike
  #   op: BinOp
  #   left, right: Clause

  # # Call = ref object of Clause
  # #   name: string
  # #   args: seq[Clause]

  # Statement = ref object of Clause

  # Select = ref object of Statement
  #   tables: seq[TableLike]
  #   joins: seq[Join]
  #   cols: seq[ColumnLike]
  #   conditions: seq[Condition]

  ExSelect = ref object of Expr
    data: Expr

var ConnectionClass: Value

proc eval_select(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value {.wrap_exception.} =
  var expr = cast[ExSelect](expr)
  var output = self.eval(frame, expr.data)
  todo("eval_select")

proc translate_select(value: Value): Expr {.wrap_exception.} =
  var e = ExSelect(
    evaluator: eval_wrap(eval_select),
  )
  var tmpl = new_gene_gene(new_gene_symbol("$render"))
  tmpl.gene_data.add(value)
  e.data = translate(tmpl)
  return e

proc open*(args: Value): Value {.wrap_exception.} =
  var db = open(args.gene_data[0].str, "", "", "")
  Value(
    kind: VkCustom,
    custom_class: ConnectionClass.class,
    custom: Connection(
      conn: db,
    ),
  )

proc exec*(self: Value, args: Value): Value {.wrap_exception.} =
  result = new_gene_vec()
  var conn = cast[Connection](self.custom).conn
  for row in conn.instant_rows(sql(args.gene_data[0].str)):
    var item = new_gene_vec()
    for i in 0..row.len():
      item.vec.add(row[i])
    result.vec.add(item)

proc close*(self: Value, args: Value): Value {.wrap_exception.} =
  cast[Connection](self.custom).conn.close()

{.push dynlib exportc.}

proc init*(): Value {.wrap_exception.} =
  result = new_namespace("sqlite")
  GENEX_NS.ns["sqlite"] = result

  result.ns["select"] = new_gene_processor(translate_select)
  result.ns["open"] = NativeFn(open)

  ConnectionClass = new_gene_class("Connection")
  result.ns["Connection"] = ConnectionClass
  ConnectionClass.def_native_method("close", method_wrap(close))
  ConnectionClass.def_native_method("exec", method_wrap(exec))

{.pop.}

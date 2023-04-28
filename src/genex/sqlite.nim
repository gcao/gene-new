import db_sqlite

include gene/extension/boilerplate

type
  CustomConnection = ref object of CustomValue
    conn: DbConn

var ConnectionClass {.threadvar.}: Value
var StatementClass {.threadvar.}: Value

proc open*(frame: Frame, args: Value): Value {.wrap_exception.} =
  var db = open(args.gene_children[0].str, "", "", "")
  new_gene_custom(CustomConnection(conn: db), ConnectionClass.class)

proc exec*(frame: Frame, self: Value, args: Value): Value {.wrap_exception.} =
  result = new_gene_vec()
  var conn = cast[CustomConnection](self.custom).conn
  var stmt: string
  var arg0 = args.gene_children[0]
  case arg0.kind
  of VkString:
    stmt = arg0.str
  else:
    todo("Connection.exec " & $arg0.kind)
  for row in conn.instant_rows(sql(stmt)):
    var item = new_gene_vec()
    for i in 0..row.len():
      item.vec.add(row[i])
    result.vec.add(item)

proc close*(frame: Frame, self: Value, args: Value): Value {.wrap_exception.} =
  cast[CustomConnection](self.custom).conn.close()

{.push dynlib exportc.}

proc init*(module: Module): Value {.wrap_exception.} =
  result = new_namespace("sqlite")
  result.ns.module = module
  VM.genex_ns.ns["sqlite"] = result

  # result.ns["select"] = new_gene_processor(translate_select)
  result.ns["open"] = NativeFn(open)

  ConnectionClass = new_gene_class("Connection")
  result.ns["Connection"] = ConnectionClass
  ConnectionClass.def_native_method("close", method_wrap(close))
  ConnectionClass.def_native_method("exec", method_wrap(exec))

  StatementClass = new_gene_class("Statement")
  result.ns["Statement"] = StatementClass
{.pop.}

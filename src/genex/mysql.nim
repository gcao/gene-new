import db_mysql

include gene/extension/boilerplate

type
  CustomConnection = ref object of CustomValue
    conn: DbConn

var ConnectionClass: Value
var StatementClass: Value

proc open*(args: Value): Value {.wrap_exception.} =
  var host = args.gene_children[0].str
  var user = args.gene_children[1].str
  var pass = args.gene_children[2].str
  var db_name = args.gene_children[3].str
  var db = open(host, user, pass, db_name)
  new_gene_custom(CustomConnection(conn: db), ConnectionClass.class)

proc exec*(self: Value, args: Value): Value {.wrap_exception.} =
  result = new_gene_vec()
  var conn = cast[CustomConnection](self.custom).conn
  var stmt: string
  var arg0 = args.gene_children[0]
  case arg0.kind
  of VkString:
    stmt = arg0.str
  else:
    todo("Connection.exec " & $arg0.kind)
  if args.gene_children.len > 1:
    for row in conn.instant_rows(sql(stmt), args.gene_children[1..^1]):
      var item = new_gene_vec()
      for i in 0..row.len():
        item.vec.add(row[i])
      result.vec.add(item)
  else:
    for row in conn.instant_rows(sql(stmt)):
      var item = new_gene_vec()
      for i in 0..row.len():
        item.vec.add(row[i])
      result.vec.add(item)

proc close*(self: Value, args: Value): Value {.wrap_exception.} =
  cast[CustomConnection](self.custom).conn.close()

{.push dynlib exportc.}

proc init*(module: Module): Value {.wrap_exception.} =
  result = new_namespace("mysql")
  result.ns.module = module
  GENEX_NS.ns["mysql"] = result

  # result.ns["select"] = new_gene_processor(translate_select)
  result.ns["open"] = NativeFn(open)

  ConnectionClass = new_gene_class("Connection")
  result.ns["Connection"] = ConnectionClass
  ConnectionClass.def_native_method("close", method_wrap(close))
  ConnectionClass.def_native_method("exec", method_wrap(exec))

  StatementClass = new_gene_class("Statement")
  result.ns["Statement"] = StatementClass
{.pop.}

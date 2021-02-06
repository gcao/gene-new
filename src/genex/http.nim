# TODO: figure out how to make global variables work across extensions

# import tables, strutils
# import asynchttpserver, asyncdispatch

# import ../gene/types
# import ../gene/interpreter

# # HTTP Server
# # https://nim-lang.org/docs/asynchttpserver.html
# # https://dev.to/xflywind/write-a-simple-web-framework-in-nim-language-from-scratch-ma0

# proc start_http_server(port: int, handler: proc(req: Request) {.async gcsafe.}) =
#   var server = new_async_http_server()
#   async_check server.serve(Port(port), handler)

# {.push dynlib exportc.}

# proc start_http_server*(props: OrderedTable[MapKey, GeneValue], data: seq[GeneValue]): GeneValue =
#   var port = if data[0].kind == GeneString:
#     data[0].str.parse_int
#   else:
#     data[0].int

#   proc handler(req: Request) {.async gcsafe.} =
#     var args = new_gene_gene(GeneNil)
#     # args.gene.data.add(req)
#     var body = VM.call_fn(GeneNil, data[1].internal.fn, args).str
#     await req.respond(Http200, body, new_http_headers())

#   start_http_server port, handler

# {.pop.}

# # when isMainModule:
# #   proc handler(req: Request) {.async.} =
# #     let headers = {"Content-type": "text/plain; charset=utf-8"}
# #     await req.respond(Http200, "Hello World", headers.new_http_headers())

# #   start_http_server(2080, handler)
# #   run_forever()

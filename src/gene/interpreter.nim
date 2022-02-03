import strutils, tables, strutils, os, sets
import asyncdispatch
# import macros

import ./map_key
import ./types
import ./parser
import ./exprs
import ./translators

# macro import_folder(s: string): untyped =
#   let s = staticExec "find " & s.toStrLit.strVal & " -name '*.nim' -maxdepth 1"
#   let files = s.splitLines
#   result = newStmtList()
#   for file in files:
#     result.add(parseStmt("import " & file[0..^5] & " as feature"))

# # Below code doesn't work for some reason
# import_folder "features"

import "./features/core" as core_feature; core_feature.init()
import "./features/symbol" as symbol_feature; symbol_feature.init()
import "./features/array" as array_feature; array_feature.init()
import "./features/map" as map_feature; map_feature.init()
import "./features/gene" as gene_feature; gene_feature.init()
import "./features/range" as range_feature; range_feature.init()
import "./features/quote" as quote_feature; quote_feature.init()
import "./features/arithmetic" as arithmetic_feature; arithmetic_feature.init()
import "./features/var" as var_feature; var_feature.init()
import "./features/assignment" as assignment_feature; assignment_feature.init()
import "./features/enum" as enum_feature; enum_feature.init()
import "./features/regex" as regex_feature; regex_feature.init()
import "./features/exception" as exception_feature; exception_feature.init()
import "./features/if" as if_feature; if_feature.init()
import "./features/if_star" as if_star_feature; if_star_feature.init()
import "./features/fp" as fp_feature; fp_feature.init()
import "./features/macro" as macro_feature; macro_feature.init()
import "./features/block" as block_feature; block_feature.init()
import "./features/async" as async_feature; async_feature.init()
import "./features/namespace" as namespace_feature; namespace_feature.init()
import "./features/selector" as selector_feature; selector_feature.init()
import "./features/native" as native_feature; native_feature.init()
import "./features/loop" as loop_feature; loop_feature.init()
import "./features/while" as while_feature; while_feature.init()
import "./features/repeat" as repeat_feature; repeat_feature.init()
import "./features/for" as for_feature; for_feature.init()
import "./features/case" as case_feature; case_feature.init()
import "./features/oop" as oop_feature; oop_feature.init()
import "./features/cast" as cast_feature; cast_feature.init()
import "./features/eval" as eval_feature; eval_feature.init()
import "./features/parse" as parse_feature; parse_feature.init()
import "./features/pattern_matching" as pattern_matching_feature; pattern_matching_feature.init()
import "./features/module" as module_feature; module_feature.init()
import "./features/hot_reload" as hot_reload_feature; hot_reload_feature.init()
import "./features/include" as include_feature; include_feature.init()
import "./features/template" as template_feature; template_feature.init()
import "./features/print" as print_feature; print_feature.init()
import "./features/repl" as repl_feature; repl_feature.init()
import "./features/parse_cmd_args" as parse_cmd_args_feature; parse_cmd_args_feature.init()
import "./features/os" as os_feature; os_feature.init()

import "./libs" as libs; libs.init()

import ../types
import ../exprs
import "../features/core" as core_feature; core_feature.init()
import "../features/symbol" as symbol_feature; symbol_feature.init()
import "../features/array" as array_feature; array_feature.init()
import "../features/map" as map_feature; map_feature.init()
import "../features/gene" as gene_feature; gene_feature.init()
import "../features/range" as range_feature; range_feature.init()
import "../features/quote" as quote_feature; quote_feature.init()
import "../features/arithmetic" as arithmetic_feature; arithmetic_feature.init()
import "../features/var" as var_feature; var_feature.init()
import "../features/assignment" as assignment_feature; assignment_feature.init()
import "../features/enum" as enum_feature; enum_feature.init()
import "../features/regex" as regex_feature; regex_feature.init()
import "../features/exception" as exception_feature; exception_feature.init()
import "../features/if" as if_feature; if_feature.init()
import "../features/fp" as fp_feature; fp_feature.init()
import "../features/macro" as macro_feature; macro_feature.init()
import "../features/block" as block_feature; block_feature.init()
import "../features/async" as async_feature; async_feature.init()
import "../features/namespace" as namespace_feature; namespace_feature.init()
import "../features/selector" as selector_feature; selector_feature.init()
import "../features/native" as native_feature; native_feature.init()
import "../features/loop" as loop_feature; loop_feature.init()
import "../features/while" as while_feature; while_feature.init()
import "../features/repeat" as repeat_feature; repeat_feature.init()
import "../features/for" as for_feature; for_feature.init()
import "../features/case" as case_feature; case_feature.init()
import "../features/oop" as oop_feature; oop_feature.init()
import "../features/cast" as cast_feature; cast_feature.init()
import "../features/eval" as eval_feature; eval_feature.init()
import "../features/parse" as parse_feature; parse_feature.init()
import "../features/pattern_matching" as pattern_matching_feature; pattern_matching_feature.init()
import "../features/module" as module_feature; module_feature.init()
import "../features/package" as package_feature; package_feature.init()
import "../features/include" as include_feature; include_feature.init()
import "../features/template" as template_feature; template_feature.init()
import "../features/print" as print_feature; print_feature.init()
import "../features/repl" as repl_feature; repl_feature.init()
import "../features/parse_cmd_args" as parse_cmd_args_feature; parse_cmd_args_feature.init()
import "../features/os" as os_feature; os_feature.init()

method to_js*(self: Expr): string {.base, locks:"unknown".} =
  if self of ExAnd: "/* ExAnd */"
  elif self of ExArguments: "/* ExArguments */"
  elif self of ExArray: "/* ExArray */"
  elif self of ExAssert: "/* ExAssert */"
  elif self of ExAssignment: "/* ExAssignment */"
  elif self of ExAsync: "/* ExAsync */"
  elif self of ExAwait: "/* ExAwait */"
  elif self of ExBinOp: "/* ExBinOp */"
  elif self of ExBind: "/* ExBind */"
  elif self of ExBlock: "/* ExBlock */"
  elif self of ExBool: "/* ExBool */"
  elif self of ExBreak: "/* ExBreak */"
  elif self of ExCallerEval: "/* ExCallerEval */"
  elif self of ExCase: "/* ExCase */"
  elif self of ExCast: "/* ExCast */"
  elif self of ExClass: "/* ExClass */"
  elif self of ExContinue: "/* ExContinue */"
  elif self of ExDebug: "/* ExDebug */"
  elif self of ExDependency: "/* ExDependency */"
  elif self of ExEmit: "/* ExEmit */"
  elif self of ExEnum: "/* ExEnum */"
  elif self of ExEval: "/* ExEval */"
  elif self of ExException: "/* ExException */"
  elif self of ExExplode: "/* ExExplode */"
  elif self of ExFn: "/* ExFn */"
  elif self of ExFor: "/* ExFor */"
  elif self of ExGene: "/* ExGene */"
  elif self of ExGroup: "/* ExGroup */"
  elif self of ExIf: "/* ExIf */"
  elif self of ExIfMain: "/* ExIfMain */"
  elif self of ExImport: "/* ExImport */"
  # elif self of ExInclude: "/* ExInclude */"
  elif self of ExInvoke: "/* ExInvoke */"
  elif self of ExInvokeDynamic: "/* ExInvokeDynamic */"
  elif self of ExInvokeSelector: "/* ExInvokeSelector */"
  elif self of ExLiteral: "/* ExLiteral */"
  elif self of ExLoop: "/* ExLoop */"
  elif self of ExMacro: "/* ExMacro */"
  elif self of ExMap: "/* ExMap */"
  # elif self of ExMatch: "/* ExMatch */"
  elif self of ExMember: "/* ExMember */"
  elif self of ExMemberMissing: "/* ExMemberMissing */"
  elif self of ExMethod: "/* ExMethod */"
  elif self of ExMethodEq: "/* ExMethodEq */"
  elif self of ExMixin: "/* ExMixin */"
  elif self of ExMyMember: "/* ExMyMember */"
  elif self of ExNames: "/* ExNames */"
  elif self of ExNamespace: "/* ExNamespace */"
  elif self of ExNew: "/* ExNew */"
  elif self of ExNot: "/* ExNot */"
  elif self of ExNsDef: "/* ExNsDef */"
  elif self of ExOnce: "/* ExOnce */"
  elif self of ExPackage: "/* ExPackage */"
  elif self of ExParse: "/* ExParse */"
  elif self of ExParseCmdArgs: "/* ExParseCmdArgs */"
  elif self of ExPrint: "/* ExPrint */"
  elif self of ExQuote: "/* ExQuote */"
  elif self of ExRange: "/* ExRange */"
  elif self of ExRegex: "/* ExRegex */"
  elif self of ExRender: "/* ExRender */"
  elif self of ExRepeat: "/* ExRepeat */"
  elif self of ExRepl: "/* ExRepl */"
  elif self of ExReturn: "/* ExReturn */"
  elif self of ExSelector: "/* ExSelector */"
  elif self of ExSelectorInvoker: "/* ExSelectorInvoker */"
  elif self of ExSelf: "/* ExSelf */"
  elif self of ExSet: "/* ExSet */"
  elif self of ExSetProp: "/* ExSetProp */"
  elif self of ExString: "/* ExString */"
  elif self of ExStrings: "/* ExStrings */"
  elif self of ExSuper: "/* ExSuper */"
  elif self of ExSymbol: "/* ExSymbol */"
  elif self of ExTap: "/* ExTap */"
  elif self of ExThrow: "/* ExThrow */"
  elif self of ExTry: "/* ExTry */"
  elif self of ExVar: "/* ExVar */"
  elif self of ExWhile: "/* ExWhile */"
  elif self of ExWith: "/* ExWith */"
  else: "/* Expr */"

method to_js*(self: ExLiteral): string =
  $self.data

method to_js*(self: ExPrint): string =
  result = "console.log("
  for i, item in self.data:
    result &= item.to_js
    if i < self.data.len:
      result &= ", "
  result &= ")"

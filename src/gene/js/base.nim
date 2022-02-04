import ../types
import ../exprs
import "../features/core"
import "../features/symbol"
import "../features/array"
import "../features/map"
import "../features/gene"
import "../features/range"
import "../features/quote"
import "../features/arithmetic"
import "../features/var"
import "../features/assignment"
import "../features/enum"
import "../features/regex"
import "../features/exception"
import "../features/if"
import "../features/fp"
import "../features/macro"
import "../features/block"
import "../features/async"
import "../features/namespace"
import "../features/selector"
import "../features/native"
import "../features/loop"
import "../features/while"
import "../features/repeat"
import "../features/for"
import "../features/case"
import "../features/oop"
import "../features/cast"
import "../features/eval"
import "../features/parse"
import "../features/pattern_matching"
import "../features/module"
import "../features/package"
import "../features/include"
import "../features/template"
import "../features/print"
import "../features/repl"
import "../features/parse_cmd_args"
import "../features/os"

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

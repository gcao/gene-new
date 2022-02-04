import ../types
import ../exprs
import ../features/print
import ../features/gene

method to_js*(self: Expr): string {.base, locks:"unknown".} =
  "/* TODO: Expr */"

method to_js*(self: ExLiteral): string =
  $self.data

method to_js*(self: ExPrint): string =
  result = "console.log("
  for i, item in self.data:
    result &= item.to_js
    if i < self.data.len:
      result &= ", "
  result &= ")"

method to_js*(self: ExGroup): string {.locks:"unknown".} =
  "/* TODO: ExGroup */"

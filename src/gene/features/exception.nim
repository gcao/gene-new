import tables

import ../types
import ../map_key
import ../translators

type
  TryParsingState = enum
    TryBody
    TryCatch
    TryCatchBody
    TryFinally

  ExTry* = ref object of Expr
    body*: Expr
    catches*: seq[(Expr, Expr)]
    `finally`*: Expr

proc eval_try(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExTry](expr)
  try:
    result = self.eval(frame, expr.body)
  except types.Exception as ex:
    frame.scope.def_member(CUR_EXCEPTION_KEY, error_to_gene(ex))
    var handled = false
    if expr.catches.len > 0:
      for catch in expr.catches.mitems:
        # check whether the thrown exception matches exception in catch statement
        var class = self.eval(frame, catch[0])
        if class == Placeholder:
          # class = GeneExceptionClass
          handled = true
          result = self.eval(frame, catch[1])
          break
        if ex.instance == nil:
          raise
        if ex.instance.is_a(class.class):
          handled = true
          result = self.eval(frame, catch[1])
          break
    if expr.finally != nil:
      try:
        discard self.eval(frame, expr.finally)
      except Return, Break:
        todo()
    if not handled:
      raise

proc translate_try(value: Value): Expr =
  var r = ExTry(
    evaluator: eval_try,
  )
  var state = TryBody
  var body: seq[Value] = @[]
  var catch_exception: Value
  var catch_body: seq[Value] = @[]
  var `finally`: seq[Value] = @[]
  for item in value.gene_data:
    case state:
    of TryBody:
      if item == CATCH:
        state = TryCatch
      elif item == FINALLY:
        state = TryFinally
      else:
        body.add(item)
    of TryCatch:
      if item == CATCH:
        not_allowed()
      elif item == FINALLY:
        not_allowed()
      else:
        state = TryCatchBody
        catch_exception = item
    of TryCatchBody:
      if item == CATCH:
        state = TryCatch
        r.catches.add((translate(catch_exception), translate(catch_body)))
        catch_exception = nil
        catch_body = @[]
      elif item == FINALLY:
        state = TryFinally
      else:
        catch_body.add(item)
    of TryFinally:
      `finally`.add(item)

  r.body = translate(body)
  if state in [TryCatch, TryCatchBody]:
    r.catches.add((translate(catch_exception), translate(catch_body)))
  elif state == TryFinally:
    if catch_exception != nil:
      r.catches.add((translate(catch_exception), translate(catch_body)))
  return r

proc init*() =
  GeneTranslators["try"] = translate_try

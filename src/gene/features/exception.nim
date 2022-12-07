import tables

import ../types
import ../map_key
import ../interpreter_base
import ./symbol

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

  ExThrow* = ref object of Expr
    first*: Expr
    second*: Expr

proc eval_try(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExTry](expr)
  try:
    result = self.eval(frame, expr.body)
  except types.Exception as ex:
    frame.scope.def_member(CUR_EXCEPTION_KEY, exception_to_value(ex))
    var handled = false
    if expr.catches.len > 0:
      for catch in expr.catches.mitems:
        # check whether the thrown exception matches exception in catch statement
        if catch[0] of ExMyMember and cast[ExMyMember](catch[0]).name.to_s == "*":
          # class = GeneExceptionClass
          handled = true
          result = self.eval(frame, catch[1])
          break
        var class = self.eval(frame, catch[0])
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
  for item in value.gene_children:
    case state:
    of TryBody:
      if item.is_symbol("catch"):
        state = TryCatch
      elif item.is_symbol("finally"):
        state = TryFinally
      else:
        body.add(item)
    of TryCatch:
      if item.is_symbol("catch"):
        not_allowed()
      elif item.is_symbol("finally"):
        not_allowed()
      else:
        state = TryCatchBody
        catch_exception = item
    of TryCatchBody:
      if item.is_symbol("catch"):
        state = TryCatch
        r.catches.add((translate(catch_exception), translate(catch_body)))
        catch_exception = nil
        catch_body = @[]
      elif item.is_symbol("finally"):
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
  if `finally`.len > 0:
    r.finally = translate(`finally`)
  return r

proc eval_throw(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  var expr = cast[ExThrow](expr)
  if expr.first != nil:
    var class = self.eval(frame, expr.first)
    if expr.second != nil:
      var message = self.eval(frame, expr.second)
      raise new_gene_exception(message.str, Value(kind: VkInstance, instance_class: class.class))
    elif class.kind == VkClass:
      raise new_gene_exception(Value(kind: VkInstance, instance_class: class.class))
    elif class.kind == VkException:
      raise class.exception
    elif class.kind == VkString:
      raise new_gene_exception(class.str, Value(kind: VkInstance, instance_class: VM.exception_class.class))
    else:
      todo()
  else:
    raise new_gene_exception(Value(kind: VkInstance, instance_class: VM.exception_class.class))

proc translate_throw(value: Value): Expr =
  var r = ExThrow(
    evaluator: eval_throw,
  )
  if value.gene_children.len > 0:
    r.first = translate(value.gene_children[0])
    if value.gene_children.len > 1:
      r.second = translate(value.gene_children[1])

  return r

proc init*() =
  GeneTranslators["try"] = translate_try
  GeneTranslators["throw"] = translate_throw

import tables, oids, strutils

import ./types
import "./compiler/if"

proc `$`*(self: Instruction): string =
  case self.kind
    of IkPushValue: "Push " & $self.arg0
    of IkLabel: "Label " & $self.label
    of IkJump: "Jump " & $self.label
    of IkJumpIfFalse: "JumpIfFalse " & $self.label
    of IkAddValue: "AddValue " & $self.arg0
    of IkLtValue: "LtValue " & $self.arg0
    of IkMapSetProp: "MapSetProp " & $self.arg0
    of IkMapSetPropValue: "MapSetPropValue " & $self.arg0 & " " & $self.arg1
    of IkArrayAddChildValue: "ArrayAddChildValue " & $self.arg0
    of IkInternal: "Internal " & $self.arg0
    else: ($self.kind)[2..^1]

proc `$`*(self: seq[Instruction]): string =
  for i, instr in self:
    result &= $i & " " & $instr & "\n"

proc `$`*(self: CompilationUnit): string =
  "CompilationUnit " & $self.id & "\n" & $self.instructions

proc `len`*(self: CompilationUnit): int =
  self.instructions.len

proc `[]`*(self: CompilationUnit, i: int): Instruction =
  self.instructions[i]

proc find_label*(self: CompilationUnit, label: Label): int =
  for i, inst in self.instructions:
    if inst.kind == IkLabel and inst.label == label:
      return i

proc find_loop_start*(self: CompilationUnit, pos: int): int =
  var pos = pos
  while pos > 0:
    pos.dec()
    if self.instructions[pos].kind == IkLoopStart:
      return pos
  not_allowed("Loop start not found")

proc find_loop_end*(self: CompilationUnit, pos: int): int =
  var pos = pos
  while pos < self.instructions.len - 1:
    pos.inc()
    if self.instructions[pos].kind == IkLoopEnd:
      return pos
  not_allowed("Loop end not found")

proc compile(self: var Compiler, input: Value)

proc compile(self: var Compiler, input: seq[Value]) =
  for i, v in input:
    self.compile(v)
    if i < input.len - 1:
      self.output.instructions.add(Instruction(kind: IkPop))

proc compile_literal(self: var Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))

proc compile_symbol(self: var Compiler, input: Value) =
  if self.quote_level > 0:
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))
  else:
    self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: input))

proc compile_complex_symbol(self: var Compiler, input: Value) =
  if self.quote_level > 0:
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))
  else:
    let first = input.csymbol[0]
    self.output.instructions.add(Instruction(kind: IkResolveSymbol, arg0: first))
    for s in input.csymbol[1..^1]:
      self.output.instructions.add(Instruction(kind: IkGetMember, arg0: s))

proc compile_array(self: var Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkArrayStart))
  for child in input.vec:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkArrayAddChild))
  self.output.instructions.add(Instruction(kind: IkArrayEnd))

proc compile_map(self: var Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkMapStart))
  for k, v in input.map:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkMapSetProp, arg0: k))
  self.output.instructions.add(Instruction(kind: IkMapEnd))

proc compile_do(self: var Compiler, input: Value) =
  self.compile(input.gene_children)

proc compile_if(self: var Compiler, input: Value) =
  normalize_if(input)
  self.compile(input.gene_props[COND_KEY])
  var elseLabel = gen_oid()
  var endLabel = gen_oid()
  self.output.instructions.add(Instruction(kind: IkJumpIfFalse, label: elseLabel))
  self.compile(input.gene_props[THEN_KEY])
  self.output.instructions.add(Instruction(kind: IkJump, label: endLabel))
  self.output.instructions.add(Instruction(kind: IkLabel, label: elseLabel))
  self.compile(input.gene_props[ELSE_KEY])
  self.output.instructions.add(Instruction(kind: IkLabel, label: endLabel))

proc compile_var(self: var Compiler, input: Value) =
  let name = input.gene_children[0]
  if input.gene_children.len > 1:
    self.compile(input.gene_children[1])
    self.output.instructions.add(Instruction(kind: IkVar, arg0: name))
  else:
    self.output.instructions.add(Instruction(kind: IkVarValue, arg0: name, arg1: Value(kind: VkNil)))

proc compile_loop(self: var Compiler, input: Value) =
  var label = gen_oid()
  self.output.instructions.add(Instruction(kind: IkLoopStart, label: label))
  self.compile(input.gene_children)
  self.output.instructions.add(Instruction(kind: IkContinue, label: label))
  self.output.instructions.add(Instruction(kind: IkLoopEnd, label: label))

proc compile_break(self: var Compiler, input: Value) =
  if input.gene_children.len > 0:
    self.compile(input.gene_children[0])
  else:
    self.output.instructions.add(Instruction(kind: IkPushNil))
  self.output.instructions.add(Instruction(kind: IkBreak))

proc compile_fn(self: var Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkFunction, arg0: input))

proc compile_return(self: var Compiler, input: Value) =
  if input.gene_children.len > 0:
    self.compile(input.gene_children[0])
  else:
    self.output.instructions.add(Instruction(kind: IkPushNil))
  self.output.instructions.add(Instruction(kind: IkReturn))

proc compile_ns(self: var Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkNamespace, arg0: input.gene_children[0]))
  if input.gene_children.len > 1:
    let body = new_gene_stream(input.gene_children[1..^1])
    self.output.instructions.add(Instruction(kind: IkPushValue, arg0: body))
    self.output.instructions.add(Instruction(kind: IkCompileInit))
    self.output.instructions.add(Instruction(kind: IkCallInit))

proc compile_gene_default(self: var Compiler, input: Value) {.inline.} =
  self.output.instructions.add(Instruction(kind: IkGeneStart))
  self.compile(input.gene_type)
  self.output.instructions.add(Instruction(kind: IkGeneSetType))
  for k, v in input.gene_props:
    self.compile(v)
    self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))
  for child in input.gene_children:
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAddChild))
  self.output.instructions.add(Instruction(kind: IkGeneEnd))

proc compile_gene(self: var Compiler, input: Value) =
  if self.quote_level > 0 or input.gene_type.is_symbol("_") or input.gene_type.kind == VkQuote:
    self.compile_gene_default(input)
    return

  let `type` = input.gene_type
  if input.gene_children.len > 0:
    var first = input.gene_children[0]
    if first.kind == VkSymbol:
      case first.str:
        of "=":
          self.compile(input.gene_children[1])
          self.output.instructions.add(Instruction(kind: IkAssign, arg0: `type`))
          return
        of "+":
          self.compile(`type`)
          self.compile(input.gene_children[1])
          self.output.instructions.add(Instruction(kind: IkAdd))
          return
        of "-":
          self.compile(`type`)
          self.compile(input.gene_children[1])
          self.output.instructions.add(Instruction(kind: IkSub))
          return
        of "*":
          self.compile(`type`)
          self.compile(input.gene_children[1])
          self.output.instructions.add(Instruction(kind: IkMul))
          return
        of "/":
          self.compile(`type`)
          self.compile(input.gene_children[1])
          self.output.instructions.add(Instruction(kind: IkDiv))
          return
        of "<":
          self.compile(`type`)
          self.compile(input.gene_children[1])
          self.output.instructions.add(Instruction(kind: IkLt))
          return
        of "<=":
          self.compile(`type`)
          self.compile(input.gene_children[1])
          self.output.instructions.add(Instruction(kind: IkLe))
          return
        of ">":
          self.compile(`type`)
          self.compile(input.gene_children[1])
          self.output.instructions.add(Instruction(kind: IkGt))
          return
        of ">=":
          self.compile(`type`)
          self.compile(input.gene_children[1])
          self.output.instructions.add(Instruction(kind: IkGe))
          return
        of "==":
          self.compile(`type`)
          self.compile(input.gene_children[1])
          self.output.instructions.add(Instruction(kind: IkEq))
          return
        of "!=":
          self.compile(`type`)
          self.compile(input.gene_children[1])
          self.output.instructions.add(Instruction(kind: IkNe))
          return
        of "&&":
          self.compile(`type`)
          self.compile(input.gene_children[1])
          self.output.instructions.add(Instruction(kind: IkAnd))
          return
        of "||":
          self.compile(`type`)
          self.compile(input.gene_children[1])
          self.output.instructions.add(Instruction(kind: IkOr))
          return
        else:
          discard

  if `type`.kind == VkSymbol:
    case `type`.str:
      of "do":
        self.compile_do(input)
        return
      of "if":
        self.compile_if(input)
        return
      of "var":
        self.compile_var(input)
        return
      of "loop":
        self.compile_loop(input)
        return
      of "break":
        self.compile_break(input)
        return
      of "fn", "fnx":
        self.compile_fn(input)
        return
      of "return":
        self.compile_return(input)
        return
      of "ns":
        self.compile_ns(input)
        return
      else:
        if `type`.str.starts_with("$_"):
          if input.gene_children.len > 1:
            not_allowed($input)
          elif input.gene_children.len == 1:
            self.compile(input.gene_children[0])
            self.output.instructions.add(Instruction(kind: IkInternal, arg0: `type`, arg1: true))
          else:
            self.output.instructions.add(Instruction(kind: IkInternal, arg0: `type`))
          return

  self.compile_gene_default(input)

proc compile(self: var Compiler, input: Value) =
  case input.kind:
    of VkInt, VkBool, VkNil:
      self.compile_literal(input)
    of VkString:
      self.compile_literal(input) # TODO
    of VkSymbol:
      self.compile_symbol(input)
    of VkComplexSymbol:
      self.compile_complex_symbol(input)
    of VkQuote:
      self.quote_level.inc()
      self.compile(input.quote)
      self.quote_level.dec()
    of VkStream:
      self.compile(input.stream)
    of VkVector:
      self.compile_array(input)
    of VkMap:
      self.compile_map(input)
    of VkGene:
      self.compile_gene(input)
    else:
      todo($input.kind)

proc compile*(input: seq[Value]): CompilationUnit =
  var self = Compiler(output: CompilationUnit(id: gen_oid()))
  self.output.instructions.add(Instruction(kind: IkStart))

  for i, v in input:
    self.compile(v)
    if i < input.len - 1:
      self.output.instructions.add(Instruction(kind: IkPop))

  self.output.instructions.add(Instruction(kind: IkEnd))
  result = self.output

proc compile*(f: var Function) =
  if f.compiled != nil:
    return

  f.compiled = compile(f.body)
  f.compiled.matcher = f.matcher

proc compile_init*(input: Value): CompilationUnit =
  var self = Compiler(output: CompilationUnit(id: gen_oid()))
  self.output.kind = CkInit
  self.output.instructions.add(Instruction(kind: IkStart))

  self.compile(input)

  self.output.instructions.add(Instruction(kind: IkEnd))
  result = self.output

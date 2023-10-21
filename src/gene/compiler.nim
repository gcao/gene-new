import tables, oids

import ./types
import "./compiler/if"

type
  CuId* = Oid
  Label* = Oid

  Compiler* = ref object
    output*: CompilationUnit

  InstructionKind* = enum
    IkNoop

    IkStart   # start a compilation unit
    IkEnd     # end a compilation unit

    IkScopeStart
    IkScopeEnd

    IkPushValue   # push value to the next slot
    IkPop

    IkLabel
    IkJump        # unconditional jump
    IkJumpIfFalse

    IkAdd
    IkAddValue    # args: literal value
    IkSub
    IkMul
    IkDiv
    IkPow

    IkLt
    IkLtValue
    IkLe
    IkGt
    IkGe
    IkEq

    IkAnd
    IkOr

    # IkApplication
    # IkPackage
    # IkModule

    IkNamespace

    IkFunction
    IkCallFunction
    IkCallFunctionNoArgs

    IkMacro
    IkCallMacro

    IkClass
    IkCallMethod
    IkCallMethodNoArgs

    IkMapStart
    IkMapSetProp        # args: key
    IkMapSetPropValue   # args: key, literal value
    IkMapEnd

    IkArrayStart
    IkArrayAddChild
    IkArrayAddChildValue # args: literal value
    IkArrayEnd

    IkGeneStart
    IkGeneStartWithType
    IkGeneStartWithTypeValue  # args: literal value
    IkGeneSetProp
    IkGeneSetPropValue        # args: key, literal value
    IkGeneAddChild
    IkGeneAddChildValue       # args: literal value
    IkGeneEnd

    IkResolveSymbol
    IkResolveComplexSymbol

    IkYield
    IkResume

  Instruction* = object
    kind*: InstructionKind
    arg0*: Value
    arg1*: Value
    arg2*: Value
    label*: Label

  CompilationUnit* = ref object
    id*: CuId
    instructions: seq[Instruction]
    labels*: Table[Label, int]

  Address* = object
    id*: CuId
    pc*: int

proc `len`*(self: CompilationUnit): int =
  self.instructions.len

proc `[]`*(self: CompilationUnit, i: int): Instruction =
  self.instructions[i]

proc find_label*(self: CompilationUnit, label: Label): int =
  for i, inst in self.instructions:
    if inst.kind == IkLabel and inst.label == label:
      return i

proc compile(self: var Compiler, input: Value)

proc compile(self: var Compiler, input: seq[Value]) =
  for i, v in input:
    self.compile(v)
    if i < input.len - 1:
      self.output.instructions.add(Instruction(kind: IkPop))

proc compile_literal(self: var Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))

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

proc compile_gene(self: var Compiler, input: Value) =
  var `type` = input.gene_type
  var first: Value
  if input.gene_children.len > 0:
    first = input.gene_children[0]
  if first.kind == VkSymbol:
    case first.str:
      of "+":
        self.compile(`type`)
        self.compile(input.gene_children[1])
        self.output.instructions.add(Instruction(kind: IkAdd))
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
      else:
        discard

  todo("Compile " & $input)

proc compile(self: var Compiler, input: Value) =
  case input.kind:
    of VkInt, VkBool:
      self.compile_literal(input)
    of VkStream:
      self.compile(input.stream)
    of VkGene:
      self.compile_gene(input)
    else:
      todo($input.kind)

proc compile*(input: seq[Value]): CompilationUnit =
  var self = Compiler(output: CompilationUnit(id: gen_oid()))
  self.output.instructions.add(Instruction(kind: IkStart))

  for v in input:
    self.compile(v)

  self.output.instructions.add(Instruction(kind: IkEnd))
  result = self.output

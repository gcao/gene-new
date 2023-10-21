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

proc `$`*(self: Instruction): string =
  case self.kind
    of IkNoop: "Noop"
    of IkStart: "Start"
    of IkEnd: "End"
    of IkScopeStart: "ScopeStart"
    of IkScopeEnd: "ScopeEnd"
    of IkPushValue: "Push " & $self.arg0
    of IkPop: "Pop"
    of IkLabel: "Label " & $self.label
    of IkJump: "Jump " & $self.label
    of IkJumpIfFalse: "JumpIfFalse " & $self.label
    of IkAdd: "Add"
    of IkAddValue: "Add " & $self.arg0
    of IkSub: "Sub"
    of IkMul: "Mul"
    of IkDiv: "Div"
    of IkPow: "Pow"
    of IkLt: "Lt"
    of IkLtValue: "Lt " & $self.arg0
    of IkLe: "Le"
    of IkGt: "Gt"
    of IkGe: "Ge"
    of IkEq: "Eq"
    of IkAnd: "And"
    of IkOr: "Or"
    of IkNamespace: "Namespace"
    of IkFunction: "Function"
    of IkCallFunction: "CallFunction"
    of IkCallFunctionNoArgs: "CallFunctionNoArgs"
    of IkMacro: "Macro"
    of IkCallMacro: "CallMacro"
    of IkClass: "Class"
    of IkCallMethod: "CallMethod"
    of IkCallMethodNoArgs: "CallMethodNoArgs"
    of IkMapStart: "MapStart"
    of IkMapSetProp: "MapSetProp " & $self.arg0
    of IkMapSetPropValue: "MapSetPropValue " & $self.arg0 & " " & $self.arg1
    of IkMapEnd: "MapEnd"
    of IkArrayStart: "ArrayStart"
    of IkArrayAddChild: "ArrayAddChild"
    of IkArrayAddChildValue: "ArrayAddChildValue " & $self.arg0
    of IkArrayEnd: "ArrayEnd"
    of IkGeneStart: "GeneStart"
    of IkGeneStartWithType: "GeneStartWithType"
    of IkGeneStartWithTypeValue: "GeneStartWithTypeValue " & $self.arg0
    else: $self.kind

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

proc compile(self: var Compiler, input: Value)

proc compile(self: var Compiler, input: seq[Value]) =
  for i, v in input:
    self.compile(v)
    if i < input.len - 1:
      self.output.instructions.add(Instruction(kind: IkPop))

proc compile_literal(self: var Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkPushValue, arg0: input))

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
      of "<":
        self.compile(`type`)
        self.compile(input.gene_children[1])
        self.output.instructions.add(Instruction(kind: IkLt))
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
    of VkInt, VkBool, VkNil:
      self.compile_literal(input)
    of VkString:
      self.compile_literal(input) # TODO
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

  for v in input:
    self.compile(v)

  self.output.instructions.add(Instruction(kind: IkEnd))
  result = self.output

import tables

import ./types

type
  CuId* = distinct string

  InstructionKind* = enum
    IkNoop

    IkStart   # start of a compilation unit
    IkEnd     # end of a compilation unit

    IkScopeStart
    IkScopeEnd

    IkSaveToDefault
    IkSave
    IkCopyFromDefault
    IkCopyToDefault

    IkJump
    IkJumpIfFalse

    IkAdd
    IkSub
    IkMul
    IkDiv
    IkPow

    IkLt
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
    IkMapSetProp
    IkMapEnd

    IkArrayStart
    IkArrayAddChild
    IkArrayEnd

    IkGeneStart
    IkGeneStartWithType
    IkGeneSetProp
    IkGeneAddChild
    IkGeneEnd

    IkResolveSymbol
    IkResolveComplexSymbol

    IkYield
    IkResume

  Instruction* = object
    kind*: InstructionKind

  CompilationUnit* = ref object
    id*: CuId
    instructions: seq[Instruction]
    labels*: Table[string, int]

  Address* = object
    id*: CuId
    pc*: int

proc `len`*(self: CompilationUnit): int =
  self.instructions.len

proc `[]`*(self: CompilationUnit, i: int): Instruction =
  self.instructions[i]

proc compile*(input: seq[Value]): CompilationUnit =
  discard

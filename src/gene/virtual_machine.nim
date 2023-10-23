import tables, oids

import ./types
import ./parser
import ./compiler

const REG_DEFAULT = 6

type
  GeneVirtualMachineState* = enum
    VmWaiting   # waiting for task
    VmRunning
    VmPaused

  GeneVirtualMachine* = ref object
    state*: GeneVirtualMachineState
    data*: GeneVirtualMachineData

  GeneVirtualMachineData* = ref object
    is_main*: bool
    cur_block*: CompilationUnit
    pc*: int
    registers*: Registers
    code_mgr*: CodeManager

  Registers* = ref object
    caller*: Caller
    scope*: Scope
    data*: array[32, Value]
    next_slot*: int

  Caller* = ref object
    address*: Address
    registers*: Registers

  CodeManager* = ref object
    data*: Table[CuId, CompilationUnit]

proc new_registers(caller: Caller): Registers =
  Registers(
    caller: caller,
    scope: new_scope(),
    next_slot: REG_DEFAULT,
  )

proc current(self: var Registers): Value =
  self.data[self.next_slot - 1]

proc push(self: var Registers, value: Value) =
  self.data[self.next_slot] = value
  self.next_slot.inc()

proc pop(self: var Registers): Value =
  self.next_slot.dec()
  self.data[self.next_slot]

proc default(self: Registers): Value =
  self.data[REG_DEFAULT]

proc new_vm_data(caller: Caller): GeneVirtualMachineData =
  result = GeneVirtualMachineData(
    is_main: false,
    cur_block: nil,
    pc: 0,
    registers: new_registers(caller),
    code_mgr: CodeManager(),
  )

proc new_vm_data(): GeneVirtualMachineData =
  new_vm_data(nil)

proc exec*(self: var GeneVirtualMachine): Value =
  while true:
    let inst = self.data.cur_block[self.data.pc]
    case inst.kind:
      of IkStart:
        # echo $self.data.cur_block
        discard

      of IkEnd:
        let v = self.data.registers.default
        if self.data.registers.caller == nil:
          return v
        else:
          todo()

      of IkVar:
        self.data.registers.scope.def_member(inst.arg0.str, self.data.registers.pop())

      of IkResolveSymbol:
        self.data.registers.push(self.data.registers.scope[inst.arg0.str])

      of IkLabel:
        discard

      of IkJump:
        self.data.pc = self.data.cur_block.find_label(inst.label) + 1
        continue
      of IkJumpIfFalse:
        if not self.data.registers.pop().bool:
          self.data.pc = self.data.cur_block.find_label(inst.label) + 1
          continue

      of IkLoopStart, IkLoopEnd:
        discard

      of IkContinue:
        self.data.pc = self.data.cur_block.find_loop_start(self.data.pc)
        continue

      of IkBreak:
        self.data.pc = self.data.cur_block.find_loop_end(self.data.pc)
        continue

      of IkPushValue:
        self.data.registers.push(inst.arg0)
      of IkPop:
        discard self.data.registers.pop()

      of IkArrayStart:
        self.data.registers.push(new_gene_vec())
      of IkArrayAddChild:
        let child = self.data.registers.pop()
        self.data.registers.current().vec.add(child)
      of IkArrayEnd:
        discard

      of IkMapStart:
        self.data.registers.push(new_gene_map())
      of IkMapSetProp:
        let key = inst.arg0.str
        let val = self.data.registers.pop()
        self.data.registers.current().map[key] = val
      of IkMapEnd:
        discard

      of IkAdd:
        self.data.registers.push(self.data.registers.pop().int + self.data.registers.pop().int)

      of IkSub:
        self.data.registers.push(-self.data.registers.pop().int + self.data.registers.pop().int)

      of IkMul:
        self.data.registers.push(self.data.registers.pop().int * self.data.registers.pop().int)

      of IkDiv:
        let second = self.data.registers.pop().int
        let first = self.data.registers.pop().int
        self.data.registers.push(first / second)

      of IkLt:
        let second = self.data.registers.pop().int
        let first = self.data.registers.pop().int
        self.data.registers.push(first < second)

      of IkLe:
        let second = self.data.registers.pop().int
        let first = self.data.registers.pop().int
        self.data.registers.push(first <= second)

      of IkAnd:
        let second = self.data.registers.pop()
        let first = self.data.registers.pop()
        self.data.registers.push(first and second)

      of IkOr:
        let second = self.data.registers.pop()
        let first = self.data.registers.pop()
        self.data.registers.push(first or second)

      else:
        todo($inst.kind)

    self.data.pc.inc
    if self.data.pc >= self.data.cur_block.len:
      break

proc exec*(code: string, module_name: string): Value =
  let compiled = compile(read_all(code))

  var vm_data = new_vm_data()
  vm_data.code_mgr.data[compiled.id] = compiled
  vm_data.cur_block = compiled

  var vm = GeneVirtualMachine(data: vm_data)
  vm.exec()

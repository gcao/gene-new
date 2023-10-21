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
    next_slot: REG_DEFAULT,
  )

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
        discard

      of IkEnd:
        let v = self.data.registers.default
        if self.data.registers.caller == nil:
          return v
        else:
          todo()

      of IkPushValue:
        self.data.registers.push(inst.arg0)

      of IkAdd:
        self.data.registers.push(self.data.registers.pop().int + self.data.registers.pop().int)

      else:
        todo()

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

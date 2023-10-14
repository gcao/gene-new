import tables

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

  Caller* = ref object
    address*: Address
    registers*: Registers

  CodeManager* = ref object
    data*: Table[CuId, CompilationUnit]

proc new_vm_data(caller: Caller): GeneVirtualMachineData =
  result = GeneVirtualMachineData(
    is_main: false,
    cur_block: nil,
    pc: 0,
    registers: Registers(caller: caller),
    code_mgr: CodeManager(),
  )

proc new_vm_data(): GeneVirtualMachineData =
  new_vm_data(nil)

proc exec*(self: var GeneVirtualMachine): Value =
  while true:
    let inst = self.data.cur_block[self.data.pc]
    case inst.kind:
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

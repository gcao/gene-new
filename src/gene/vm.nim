import tables, oids, strutils

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

proc parse*(self: var RootMatcher, v: Value)

proc calc_next*(self: var Matcher) =
  var last: Matcher = nil
  for m in self.children.mitems:
    m.calc_next()
    if m.kind in @[MatchData, MatchLiteral]:
      if last != nil:
        last.next = m
      last = m

proc calc_next*(self: var RootMatcher) =
  var last: Matcher = nil
  for m in self.children.mitems:
    m.calc_next()
    if m.kind in @[MatchData, MatchLiteral]:
      if last != nil:
        last.next = m
      last = m

proc calc_min_left*(self: var Matcher) =
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    var m = self.children[i]
    m.calc_min_left()
    m.min_left = min_left
    if m.required:
      min_left += 1

proc calc_min_left*(self: var RootMatcher) =
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    var m = self.children[i]
    m.calc_min_left()
    m.min_left = min_left
    if m.required:
      min_left += 1

proc parse(self: var RootMatcher, group: var seq[Matcher], v: Value) =
  case v.kind:
  of VkSymbol:
    if v.str[0] == '^':
      var m = new_matcher(self, MatchProp)
      if v.str.ends_with("..."):
        m.is_splat = true
        if v.str[1] == '^':
          m.name = v.str[2..^4]
          m.is_prop = true
        else:
          m.name = v.str[1..^4]
      else:
        if v.str[1] == '^':
          m.name = v.str[2..^1]
          m.is_prop = true
        else:
          m.name = v.str[1..^1]
      group.add(m)
    else:
      var m = new_matcher(self, MatchData)
      group.add(m)
      if v.str != "_":
        if v.str.ends_with("..."):
          m.is_splat = true
          if v.str[0] == '^':
            m.name = v.str[1..^4]
            m.is_prop = true
          else:
            m.name = v.str[0..^4]
        else:
          if v.str[0] == '^':
            m.name = v.str[1..^1]
            m.is_prop = true
          else:
            m.name = v.str
  of VkComplexSymbol:
    if v.csymbol[0] == '^':
      todo("parse " & $v)
    else:
      var m = new_matcher(self, MatchData)
      group.add(m)
      m.is_prop = true
      var name = v.csymbol[1]
      if name.ends_with("..."):
        m.is_splat = true
        m.name = name[0..^4]
      else:
        m.name = name
  of VkVector:
    var i = 0
    while i < v.vec.len:
      var item = v.vec[i]
      i += 1
      if item.kind == VkVector:
        var m = new_matcher(self, MatchData)
        group.add(m)
        self.parse(m.children, item)
      else:
        self.parse(group, item)
        if i < v.vec.len and v.vec[i].is_symbol("="):
          todo("Support default values")
          # i += 1
          # var last_matcher = group[^1]
          # var value = v.vec[i]
          # i += 1
          # last_matcher.default_value_expr = translate(value)
  of VkQuote:
    var m = new_matcher(self, MatchLiteral)
    m.literal = v.quote
    m.name = "<literal>"
    group.add(m)
  else:
    todo("parse " & $v.kind)

proc parse*(self: var RootMatcher, v: Value) =
  if v == nil or v == new_gene_symbol("_"):
    return
  self.parse(self.children, v)
  self.calc_min_left()
  self.calc_next()

proc new_arg_matcher*(value: Value): RootMatcher =
  result = new_arg_matcher()
  result.parse(value)

proc to_function*(node: Value): Function {.gcsafe.} =
  var name: string
  var matcher = new_arg_matcher()
  var body_start: int
  case node.gene_type.str:
  of "fnx":
    matcher.parse(node.gene_children[0])
    name = "<unnamed>"
    body_start = 1
  of "fnxx":
    name = "<unnamed>"
    body_start = 0
  else:
    var first = node.gene_children[0]
    case first.kind:
    of VkSymbol, VkString:
      name = first.str
    of VkComplexSymbol:
      name = first.csymbol[^1]
    else:
      todo($first.kind)

    matcher.parse(node.gene_children[1])
    body_start = 2

  var body: seq[Value] = @[]
  for i in body_start..<node.gene_children.len:
    body.add node.gene_children[i]

  body = wrap_with_try(body)
  result = new_fn(name, matcher, body)
  result.async = node.gene_props.get_or_default("async", false)

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

      of IkVar:
        let value = self.data.registers.pop()
        self.data.registers.scope.def_member(inst.arg0.str, value)
        self.data.registers.push(value)

      of IkAssign:
        let value = self.data.registers.current()
        self.data.registers.scope[inst.arg0.str] = value

      of IkResolveSymbol:
        case inst.arg0.str:
          of "_":
            self.data.registers.push(Value(kind: VkPlaceholder))
          else:
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
      of IkPushNil:
        self.data.registers.push(Value(kind: VkNil))
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

      of IkGeneStart:
        self.data.registers.push(new_gene_gene())
      of IkGeneSetType:
        let val = self.data.registers.pop()
        self.data.registers.current().gene_type = val
      of IkGeneSetProp:
        let key = inst.arg0.str
        let val = self.data.registers.pop()
        self.data.registers.current().gene_props[key] = val
      of IkGeneAddChild:
        let child = self.data.registers.pop()
        self.data.registers.current().gene_children.add(child)
      of IkGeneEnd:
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

      of IkGt:
        let second = self.data.registers.pop().int
        let first = self.data.registers.pop().int
        self.data.registers.push(first > second)

      of IkGe:
        let second = self.data.registers.pop().int
        let first = self.data.registers.pop().int
        self.data.registers.push(first >= second)

      of IkEq:
        let second = self.data.registers.pop().int
        let first = self.data.registers.pop().int
        self.data.registers.push(first == second)

      of IkNe:
        let second = self.data.registers.pop().int
        let first = self.data.registers.pop().int
        self.data.registers.push(first != second)

      of IkAnd:
        let second = self.data.registers.pop()
        let first = self.data.registers.pop()
        self.data.registers.push(first and second)

      of IkOr:
        let second = self.data.registers.pop()
        let first = self.data.registers.pop()
        self.data.registers.push(first or second)

      of IkFunction:
        var f = to_function(inst.arg0)
        # f.ns = frame.ns
        # f.parent_scope = frame.scope
        # f.parent_scope_max = frame.scope.max
        self.data.registers.push(Value(kind: VkFunction, fn: f))

      of IkInternal:
        case inst.arg0.str:
          of "$_debug":
            if inst.arg1:
              echo "$_debug ", self.data.registers.current()
          of "$_print_instructions":
            echo self.data.cur_block
            if inst.arg1:
              discard self.data.registers.pop()
            self.data.registers.push(Value(kind: VkNil))
          of "$_print_registers":
            var s = "Registers "
            for i, reg in self.data.registers.data:
              if i > 0:
                s &= ", "
              if i == self.data.registers.next_slot:
                s &= "=> "
              s &= $self.data.registers.data[i]
            echo s
            if inst.arg1:
              discard self.data.registers.pop()
              self.data.registers.push(Value(kind: VkNil))
          else:
            todo(inst.arg0.str)

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

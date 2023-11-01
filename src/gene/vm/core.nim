proc to_ctor(node: Value): Function =
  var name = "ctor"

  var matcher = new_arg_matcher()
  matcher.parse(node.gene_children[0])

  var body: seq[Value] = @[]
  for i in 1..<node.gene_children.len:
    body.add node.gene_children[i]

  body = wrap_with_try(body)
  result = new_fn(name, matcher, body)

proc class_ctor(vm_data: VirtualMachineData, args: Value): Value =
  var fn = to_ctor(args)
  fn.ns = vm_data.registers.ns
  vm_data.registers.self.class.constructor = Value(kind: VkFunction, fn: fn)

proc class_fn(vm_data: VirtualMachineData, args: Value): Value =
  let self = args.gene_type.bound_method.self
  # define a fn like method on a class
  var fn = to_function(args)

  var m = Method(
    name: fn.name,
    callable: Value(kind: VkFunction, fn: fn),
  )
  case self.kind:
  of VkClass:
    m.class = self.class
    fn.ns = self.class.ns
    self.class.methods[m.name] = m
  of VkMixin:
    fn.ns = self.mixin.ns
    self.mixin.methods[m.name] = m
  else:
    not_allowed()

VMCreatedCallbacks.add proc() =
  App.app.class_class = Value(kind: VkClass, class: new_class("Class"))
  App.app.class_class.def_native_macro_method "ctor", class_ctor
  App.app.class_class.def_native_macro_method "fn", class_fn

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
  App.app.class_class.def_native_macro_method "fn", class_fn

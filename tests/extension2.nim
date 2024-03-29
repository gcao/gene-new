include gene/extension/boilerplate

type
  Extension2 = ref object of CustomValue
    name: string

{.push dynlib exportc.}

proc new_extension2*(frame: Frame, args: Value): Value {.wrap_exception.} =
  Value(
    kind: VkCustom,
    custom: Extension2(
      name: args.gene_children[0].str,
    ),
  )

proc extension2_name*(frame: Frame, args: Value): Value {.wrap_exception.} =
  Extension2(args.gene_children[0].custom).name

{.pop.}

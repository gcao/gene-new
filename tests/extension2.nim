include gene/ext_common

type
  Extension2 = ref object of CustomValue
    name: string

{.push dynlib exportc.}

proc new_extension2*(args: Value): Value {.nimcall, wrap_exception.} =
  Value(
    kind: VkCustom,
    custom: Extension2(
      name: args.gene_data[0].str,
    ),
  )

proc extension2_name*(args: Value): Value {.nimcall, wrap_exception.} =
  Extension2(args.gene_data[0].custom).name

{.pop.}

include gene/ext_common

type
  Extension2 = ref object of CustomValue
    name: string

{.push dynlib exportc.}

proc new_extension2*(args: Value): Value {.nimcall.} =
  echo "new_extension2"
  result = Value(
    kind: VkCustom,
    custom: Extension2(
      name: args.gene_data[0].str,
    ),
  )

proc extension2_name*(args: Value): Value {.nimcall.} =
  echo "extension2_name"
  Extension2(args[0].custom).name

{.pop.}

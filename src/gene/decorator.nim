import tables

import ./map_key
import ./types

proc is_decorator(v: GeneValue): bool =
  case v.kind:
  of GeneSymbol:
    var s = v.symbol
    return s[0] == '+' and s != "+" and s != "+="
  of GeneGene:
    return v.gene.type.is_decorator()
  else:
    return false

proc decorate(target, with: GeneValue): GeneValue =
  result = new_gene_gene(Call)
  result.gene.props[DECORATOR_KEY] = GeneTrue
  case with.kind:
  of GeneSymbol:
    result.gene.data.add(new_gene_symbol(with.symbol[1..^1]))
  of GeneGene:
    with.gene.type = new_gene_symbol(with.gene.type.symbol[1..^1])
    result.gene.data.add(with)
  else:
    not_allowed()
  result.gene.data.add(new_gene_vec(@[target]))

proc process_decorators*(input: seq[GeneValue]): seq[GeneValue] =
  var has_decorator = false
  for item in input:
    if item.is_decorator():
      has_decorator = true
      break
  if has_decorator:
    result = @[]
    var target = input[^1]
    var i = input.len - 2
    while i >= 0:
      var item = input[i]
      i -= 1
      if item.is_decorator():
        target = decorate(target, item)
      else:
        result.insert(target, 0)
        target = item
    result.insert(target, 0)
  else:
    return input

proc process_decorators*(input: GeneValue) =
  case input.kind:
  of GeneVector:
    input.vec = process_decorators(input.vec)
  of GeneGene:
    input.gene.data = process_decorators(input.gene.data)
  else:
    discard

{.push dynlib exportc.}

import tables

import gene/types

proc test*(props: OrderedTable[string, GeneValue], data: seq[GeneValue]): GeneValue =
  var first = data[0].int
  var second = data[1].int
  return new_gene_int(first + second)

# proc test_call_gene_fn*(props: OrderedTable[string, GeneValue], data: seq[GeneValue]): GeneValue =
#   var fn   = data[0]
#   var args = new_gene_gene(GeneNil)
#   args.gene.props = data[1].map
#   args.gene.data  = data[2].vec
#   VM.call_fn(GeneNil, fn, args)

{.pop.}

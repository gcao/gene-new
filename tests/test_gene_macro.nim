# Support macro language
#
# * Operate on Gene input and system resources (e.g. environment,
#   file system, socket connection, databases, other IO devices etc)
# * Output can be Gene data or string / binary output ?!

# test_parser """
#   (#def a [1])
#   ##a
# """, @[new_gene_int(1)]
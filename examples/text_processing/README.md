# Text Processing

https://github.com/gcao/gene.nim/issues/9

```bash
cat examples/text_processing/test.csv | gene --im csv --pr --eval '(v .@1)'

cat examples/text_processing/test.csv | gene --csv --pr --fr --eval '(if (i < 5) (v .@1))'

cat examples/text_processing/test.csv | gene --csv --sf --pr --fr --eval '(if (i < 5) (v .@1))'

gene --eval '(println "In eval")(repl)'

# No space is allowed between short option and its value
gene -e'(println "In eval")(repl)'

cat src/gene.gene | gene --gene --pr --fr --eval '(if (i < 5) v)'

cat examples/io.gene | gene --line --pr --sf --se --eval 'v'
```

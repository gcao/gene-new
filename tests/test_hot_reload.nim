# HOT RELOAD
# Module must be marked as reloadable first
# We need symbol table per module
# Symbols are referenced by names/keys
# Should work for imported symbols, e.g. (import a from "a")
# Should work for aliases when a symbol is imported, e.g. (import a as b from "a")
# Should not reload `b` if `b` is defined like (import a from "a") (var b a)
# Should work for child members of imported symbols, e.g. (import a from "a") a/b

# Reload occurs in the same thread at controllable interval.
# https://github.com/paul-nameless/nim-fswatch
# https://github.com/FedericoCeratto/nim-fswatch

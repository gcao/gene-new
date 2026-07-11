# Gene Alternative Indentation Format (`.geni`)

> Status: design proposal

## Summary

Gene's regular `.gene` syntax represents structure explicitly with parentheses:

```gene
(fn add [a b]
  (a + b)
)
```

The alternative `.geni` format uses indentation to express the same structure:

```geni
fn add [a b]
  a + b
```

The purpose of `.geni` is to make ordinary programs, tree-shaped DSLs, HTML, configuration, and builder-style code easier to read and write without changing Gene's underlying data model.

`.gene` remains the explicit reference source syntax. `.geni` is a human-oriented reader syntax that must desugar deterministically to the same Gene node tree.

The two formats have the same runtime semantics:

```text
.geni source -> Gene AST -> evaluation
.gene source -> Gene AST -> evaluation
```

A formatter or debugger should be able to show the explicit `.gene` form of any `.geni` construct.

## Design goals

1. Preserve Gene's homoiconic `head + properties + children` model.
2. Remove most structural parentheses from ordinary source code.
3. Make indentation correspond closely to the resulting Gene tree.
4. Retain parentheses as an explicit escape hatch for dense or ambiguous expressions.
5. Keep conversion between `.gene` and `.geni` deterministic.
6. Ensure ordinary comments never affect program semantics.
7. Use visibly distinct reader directives for exceptional layout behavior.

## 1. Basic layout rule

A non-empty logical line normally defines one Gene form. Tokens on the same line form its head, properties, and arguments. More-indented lines become its body.

For example:

```geni
fn add [a b]
  a + b
```

is equivalent to:

```gene
(fn add [a b]
  (a + b)
)
```

Likewise:

```geni
class Query
  .ctor /table

  .fn where /where

  .fn limit /limit
```

is equivalent to:

```gene
(class Query
  (.ctor /table)

  (.fn where /where)

  (.fn limit /limit)
)
```

Blank lines do not affect the AST.

Normal comments use `#` and are non-semantic:

```geni
# This comment never changes parsing behavior.
var port 2080
```

## 2. Same-line expressions

Simple forms can stay on one line:

```geni
import genex/http/*
var port 2080
println "Starting server" port
```

Equivalent `.gene`:

```gene
(import genex/http/*)
(var port 2080)
(println "Starting server" port)
```

Properties remain part of the same Gene form:

```geni
INPUT ^type "checkbox" ^checked /.done
```

Equivalent `.gene`:

```gene
(INPUT ^type "checkbox" ^checked /.done)
```

## 3. Nested calls and explicit parentheses

Indentation is not intended to eliminate all parentheses. Parentheses remain useful for nested calls, grouping, and expressions whose compact form is clearer.

```geni
var conn (DB/open DB_HOST DB_USER DB_PASS DB_NAME)
var query (new Query /table)
var data (/orm .exec query id)
```

Equivalent `.gene`:

```gene
(var conn (DB/open DB_HOST DB_USER DB_PASS DB_NAME))
(var query (new Query /table))
(var data (/orm .exec query id))
```

Dense boolean expressions may also remain parenthesized:

```geni
(req/.path == /path) && (/http_methods/.empty || (/http_methods .contains req/.method))
```

The `.geni` formatter may choose explicit parentheses whenever indentation-only output would be harder to understand.

## 4. Direct value lines with `=`

Under the normal layout rule, a line is interpreted as a form. Sometimes a block needs to contain a value expression directly rather than wrapping that line as another form.

A line beginning with `=` contributes the following expression directly to the enclosing form.

```geni
.fn to_s _
  var sql "SELECT * FROM todos"
  = sql
```

Equivalent `.gene`:

```gene
(.fn to_s _
  (var sql "SELECT * FROM todos")
  sql
)
```

Another example:

```geni
var port
  if ($cmd_args/.size > 1)
    = $cmd_args/1/.to_i
  else
    = 2080
```

Equivalent `.gene`:

```gene
(var port
  (if ($cmd_args/.size > 1)
    $cmd_args/1/.to_i
  else
    2080
  )
)
```

`=` is a reader marker in this position, not assignment. Regular assignment remains unchanged:

```geni
/status = 1
```

## 5. Clause continuation words

Some forms contain clauses that conceptually belong to the same expression. Words such as `else`, `elif`, `when`, `then`, `catch`, and `finally` may continue an owning form when they appear at the appropriate indentation level.

### `if` / `else`

```geni
if /select
  sql .append (/select .join ",") " "
else
  sql .append "* "
```

Equivalent `.gene`:

```gene
(if /select
  (sql .append (/select .join ",") " ")
else
  (sql .append "* ")
)
```

### Multiline condition with `then`

```geni
if
  $cmd_args/.size > 1
then
  = $cmd_args/1/.to_i
else
  = 2080
```

Equivalent `.gene`:

```gene
(if
  ($cmd_args/.size > 1)
then
  $cmd_args/1/.to_i
else
  2080
)
```

### `case` / `when`

```geni
case payload/type
when "create"
  var todo (new Todo payload/data)
  todo .save
when "delete"
  var todo (Todo . Todo/find payload/data)
  todo .delete
else
  println "Unsupported operation" payload/type
```

Equivalent `.gene`:

```gene
(case payload/type
when "create"
  (var todo (new Todo payload/data))
  (todo .save)
when "delete"
  (var todo (Todo . Todo/find payload/data))
  (todo .delete)
else
  (println "Unsupported operation" payload/type)
)
```

The recognized continuation words should be a small, explicit parser table associated with the forms that support them. They should not be inferred from arbitrary identifiers.

## 6. Anonymous functions and application

Parentheses can group a multiline expression and allow it to be applied:

```geni
(fnx [a b]
  a + b
) 1 2
```

Equivalent `.gene`:

```gene
((fnx [a b]
  (a + b)
) 1 2)
```

A semicolon may also separate application segments. Semicolon application is reader sugar that folds segments from left to right, making the accumulated expression the head of the next segment.

```geni
fnx [a b]
  a + b
; 1 2
```

Equivalent `.gene`:

```gene
((fnx [a b]
  (a + b)
) 1 2)
```

The general rule is:

```gene
(a; b c; d)
```

becomes:

```gene
(((a) b c) d)
```

This rule should remain independent of indentation: indentation constructs each segment, and `;` combines the completed segments.

## 7. Tree-shaped DSLs

The largest readability improvement appears in tree-shaped code such as HTML.

```geni
LI ^class "todo__item"
  DIV
    INPUT ^type "checkbox" ^id /id ^checked /.done
    LABEL ^for /id
      = /description
  BUTTON ^type "button" ^data-id /id
    SVG ^width "24" ^height "24"
      LINE ^x1 "18" ^y1 "6" ^x2 "6" ^y2 "18"
      LINE ^x1 "6" ^y1 "6" ^x2 "18" ^y2 "18"
```

Equivalent `.gene`:

```gene
(LI ^class "todo__item"
  (DIV
    (INPUT ^type "checkbox" ^id /id ^checked /.done)
    (LABEL ^for /id
      /description
    )
  )
  (BUTTON ^type "button" ^data-id /id
    (SVG ^width "24" ^height "24"
      (LINE ^x1 "18" ^y1 "6" ^x2 "6" ^y2 "18")
      (LINE ^x1 "6" ^y1 "6" ^x2 "18" ^y2 "18")
    )
  )
)
```

The visual indentation closely matches the Gene node tree while preserving properties and positional children.

## 8. Reader directives

Some data-oriented forms need several indented values to become direct arguments of the parent rather than separate wrapped forms.

Ordinary comments must not change parsing. Therefore this behavior uses a reader directive beginning with `#!`, not a normal `#` comment.

### `#!args`

`#!args` changes the current indentation frame to argument-splicing mode. Subsequent expressions at that indentation level are appended directly to the parent form.

```geni
List
  #!args
  1
  2
```

Equivalent `.gene`:

```gene
(List 1 2)
```

Without the directive, the normal wrapping rule applies:

```geni
List
  1
  2
```

Equivalent conceptual `.gene`:

```gene
(List
  (1)
  (2)
)
```

The directive therefore makes an otherwise implicit structural distinction explicit.

### Multiple arguments per line

All top-level expressions on a line in argument-splicing mode are appended to the parent:

```geni
List
  #!args
  1 2 3
  4 5 6
```

Equivalent `.gene`:

```gene
(List 1 2 3 4 5 6)
```

Properties are parsed using the normal Gene rules:

```geni
Node
  #!args
  ^name "example"
  ^enabled true
  value
```

Equivalent `.gene`:

```gene
(Node ^name "example" ^enabled true value)
```

### Nested forms inside `#!args`

A line with its own indented body still constructs one complete expression. That expression is appended as one argument.

```geni
Call
  #!args
  fnx [a b]
    a + b
  1
  2
```

Equivalent `.gene`:

```gene
(Call
  (fnx [a b]
    (a + b)
  )
  1
  2
)
```

The directive affects wrapping at its own indentation level; it does not flatten the internal structure of nested forms.

## 9. Explicit directive termination with `#!end`

A directive is automatically closed by dedenting out of its indentation frame. It may also be paired with `#!end` at the same indentation level.

```geni
List
  #!args
  1
  2
  #!end
```

Equivalent `.gene`:

```gene
(List 1 2)
```

The explicit terminator is useful when normal layout resumes within the same parent block:

```geni
Container
  Header "Numbers"

  #!args
  1
  2
  #!end

  Footer "Done"
```

Equivalent `.gene`:

```gene
(Container
  (Header "Numbers")
  1
  2
  (Footer "Done")
)
```

Rules for `#!end`:

- It closes the most recent active reader directive in the same indentation frame.
- It must align with the directive it closes.
- It produces no AST node.
- `#!end` without an active directive is a reader error.
- Dedentation still closes the directive when `#!end` is omitted.

Reader directives may be represented internally with a small stack so future directives can follow the same nesting rules.

## 10. Reader-directive syntax

Lines beginning with `#!` are reserved for reader directives:

```geni
#!args
#!end
```

They are distinct from:

- normal comments beginning with `#`;
- Gene properties beginning with `^`;
- runtime forms and macros;
- metadata stored in the resulting Gene value.

Reader directives affect source parsing but do not appear in the resulting AST.

A formatter must preserve directives when emitting `.geni`, unless it replaces them with an exactly equivalent unambiguous representation.

The initial directive set should remain deliberately small:

```text
#!args
#!end
```

Additional directives should only be introduced for parsing behavior that cannot be expressed clearly with ordinary Gene forms.

## 11. Suggested parsing model

The `.geni` reader can be implemented as an indentation-aware layer over the existing Gene reader.

Each indentation frame records:

```text
parent expression
current parsing mode: normal | args
last expression created at this level
directive stack
```

Conceptually:

1. Tokenize strings, collections, explicit parentheses, and other existing Gene syntax normally.
2. Split the source into logical lines.
3. Maintain an indentation stack.
4. In normal mode, convert each logical line and its nested block into one Gene form.
5. In `args` mode, append the line's top-level expressions directly to the frame's parent.
6. Attach a more-indented block to the last expression constructed on the preceding line.
7. Process clause-continuation words before creating an unrelated sibling form.
8. Process `#!args` and `#!end` as reader state changes, not AST nodes.
9. Use explicit parentheses whenever they occur; layout must not reinterpret their internal structure.

## 12. Errors and validation

The reader should reject structurally unclear input rather than guessing.

Recommended errors include:

- inconsistent indentation;
- mixing tabs and spaces in indentation;
- indentation without a preceding form that can own a body;
- `#!end` without a matching directive;
- `#!end` at a different indentation level from its opener;
- a continuation word with no compatible owning form;
- ambiguous semicolon placement;
- a reader directive appearing where no indentation frame exists.

A standard formatter should normalize indentation. Two spaces per level is a reasonable default, while the parser may accept another consistent width.

## 13. Round-trip requirement

The central correctness property is AST equivalence:

```text
parse_geni(source) == parse_gene(format_gene(parse_geni(source)))
```

Likewise, when the `.geni` formatter can represent a Gene tree without ambiguity:

```text
parse_gene(source) == parse_geni(format_geni(parse_gene(source)))
```

Comments and exact whitespace may not round-trip unless explicitly preserved by tooling, but the Gene node tree must.

`.gene` is therefore the useful explicit form for:

- reader and parser tests;
- macro debugging;
- AST inspection;
- canonical examples of desugaring;
- cases where layout syntax would be less clear.

`.geni` is the preferred human-oriented form for:

- application code;
- class and function definitions;
- controllers and routing;
- HTML/XML-like DSLs;
- configuration and builder-style code;
- deeply nested tree structures.

## 14. Complete example

### `.geni`

```geni
class App
  .ctor /port
    /middlewares = []

  .fn construct_handler middleware_index
    if (middleware_index < /middlewares/.size)
      var middleware (/middlewares ./ middleware_index)
      var handler (.construct_handler (middleware_index + 1))
      middleware handler
    else
      = /handler

  .fn start _
    println "Starting HTTP server at port" /port "..."
    var root_handler (.construct_handler 0)
    start_server /port root_handler ^websocket /websocket
    gene/run_forever

var app
  $tap (new App 2080)
    /handler = (create_router)
    /websocket = {
      ^path "/ws"
      ^handler (new WebSocketHandler)
    }

app .start
```

### Equivalent `.gene`

```gene
(class App
  (.ctor /port
    (/middlewares = [])
  )

  (.fn construct_handler middleware_index
    (if (middleware_index < /middlewares/.size)
      (var middleware (/middlewares ./ middleware_index))
      (var handler (.construct_handler (middleware_index + 1)))
      (middleware handler)
    else
      /handler
    )
  )

  (.fn start _
    (println "Starting HTTP server at port" /port "...")
    (var root_handler (.construct_handler 0))
    (start_server /port root_handler ^websocket /websocket)
    (gene/run_forever)
  )
)

(var app
  ($tap (new App 2080)
    (/handler = (create_router))
    (/websocket = {
      ^path "/ws"
      ^handler (new WebSocketHandler)
    })
  )
)

(app .start)
```

## Conclusion

`.geni` should be treated as an alternative reader syntax for the same Gene language, not as a second language or a distinct AST.

Its normal rule is simple: each logical line forms a Gene expression, and indentation supplies its body. Parentheses remain available for explicit grouping. Clause words, direct value lines, semicolon application, and reader directives handle the cases where the normal rule is insufficient.

The `#!args` / `#!end` mechanism provides an explicit, local way to suppress normal same-level wrapping:

```geni
List
  #!args
  1
  2
  #!end
```

becomes:

```gene
(List 1 2)
```

Because `#!args` is visibly a reader directive rather than a normal comment, the syntax remains understandable to readers and safe for formatters, linters, editors, and other tools.
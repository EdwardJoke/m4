---
name: m4-coder
description: Write correct m4 language code — statically typed, indentation-sensitive, 15-keyword scripting language
---

# m4 Coder

Write syntactically correct, idiomatic m4 code. Reference `SPEC.md` for the full language specification.

## Critical Rules

1. **No braces, no semicolons** — blocks are indentation-sensitive only
2. **15 keywords max** — `let mut fun pub if elif else loop for continue esc ret nil use type`
3. **Explicit types preferred** — `let x i32 = 10` not `let x = 10`
4. **Functions need `ret`** — no implicit returns
5. **`pub fun main() i32`** is the entry point
6. **Indent with 4 spaces** — mixed indentation is invalid
7. **No `()` around conditions** — `if x > 10` not `if (x > 10)`

## Type System

```
Primitives:  i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool char str bytes
Generics:    vec[T]  map[K V]  opt[T]  res[T E]
Literals:    42  3.14  true  false  "string"  nil
```

Type declarations:
```m4
type User
    name str
    age  i32
```

## Syntax Reference

### Variables
```m4
let name str = "m4"       # immutable
mut counter i32 = 0        # mutable
```

### Functions
```m4
fun add(a i32, b i32) i32
    ret a + b

pub fun main() i32
    io.println(add(3, 4))
    ret 0
```

### Control Flow
```m4
if score > 90
    io.println("A")
elif score > 80
    io.println("B")
else
    io.println("C")

loop
    io.println("forever")
    if stop
        esc

for item in items
    io.println(item)
```

### Operators
```
Arithmetic:  +  -  *  /  %
Comparison:  ==  !=  >  <  >=  <=
Logical:     &&  ||  !
```

### String operations
```
"hello" + " world"        # concatenation
s[i]                      # indexing (0-based)
len(s)                    # length (built-in, no parens needed)
```

### Data Structures
```m4
let nums vec[i32] = [1, 2, 3, 4, 5]
nums[0]                     # indexing
for n in nums {}            # iteration

let user = User(name: "edward", age: 20)  # struct literal
user.name                   # field access (uppercase type = struct)
```

### Error Handling
```m4
let result res[T E]
let val = result?           # error propagation with ?
```

### Modules
```m4
use io                     # I/O module
use std                    # standard library
use thread                 # threading

io.println("text")         # print with newline
io.print("no newline")     # print without newline
std.range(1, 10, 2)        # range: start, end, step
```

## RE���L / Execute
```
$ m4 file.m4               # run file
$ m4 -                     # run from stdin
$ m4                       # launch REPL
$ m4 lint file.m4          # type-check only
$ m4 build file.m4         # compile to native binary
$ m4 -d file.m4            # show bytecode
$ m4 -f file.m4            # format source
```

## Common Pitfalls

- **Don't use braces or semicolons** — m4 is indentation-sensitive
- **Don't write `if (x)`** — parentheses around conditions are invalid
- **Don't omit `ret`** — functions need explicit return statements
- **Don't use `//` for comments** — use `#` for single-line comments
- **Don't use `fn` or `func`** — the keyword is `fun`
- **Don't use `var`** — use `let` (immutable) or `mut` (mutable)
- **Don't use `break`** — use `esc` to exit loops
- **Don't expect `[]` array literal** — use `vec[T]` type with list syntax
- **Don't use `class`** — use `type` for struct-like declarations
- **Don't use `import`** — use `use` for module imports

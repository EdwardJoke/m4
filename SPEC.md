# Maple Language Specification (Draft v0.1)

## Overview

Maple is a statically typed, AI-native scripting language designed for:

* fast execution
* low memory usage
* deterministic syntax
* canonical formatting
* high LLM generation reliability
* minimal grammar complexity

Maple emphasizes:

* explicitness
* predictable parsing
* low token usage
* stable AST generation
* minimal keywords

The language is indentation-sensitive and does not use `{}` block delimiters.

---

# Design Goals

## Mapleary Goals

1. Fast execution
2. Low memory usage
3. Static typing
4. Small compiler/runtime
5. Deterministic syntax
6. LLM-friendly code generation
7. Minimal punctuation
8. Canonical formatting

---

# Language Principles

## 1. One Obvious Syntax

Every construct should have:

* one preferred representation
* one parse path
* one canonical format

Syntax aliases are forbidden.

---

## 2. Indentation Defines Blocks

Maple does not use:

* `{`
* `}`
* semicolons

Blocks are defined by indentation only.

Example:

```maple
if x > 10
    io.println("large")
else
    io.println("small")
```

---

## 3. Explicit Types Preferred

Types should be written explicitly whenever practical.

Preferred:

```maple
let x i32 = 10
```

Avoid implicit inference in public APIs.

---

## 4. Minimal Grammar Entropy

The grammar must avoid:

* optional syntax forms
* context-sensitive parsing
* symbolic DSL patterns
* operator overloading complexity

---

# Keyword Set

Maple is limited to a maximum of 15 keywords.

## Reserved Keywords

| Keyword  | Purpose                 |
| -------- | ----------------------- |
| let      | immutable variable      |
| mut      | mutable variable        |
| fun      | function declaration    |
| pub      | public declaration      |
| if       | conditional             |
| elif     | alternative conditional |
| else     | fallback conditional    |
| loop     | infinite loop           |
| for      | iteration               |
| continue | loop continuation       |
| esc      | loop exit               |
| ret      | return                  |
| nil      | null value              |
| use      | module import           |
| type     | type declaration        |

Total: 15 keywords.

---

# Lexical Rules

## Significant Indentation

The lexer emits:

* INDENT
* DEDENT
* NEWLINE

Indentation determines block ownership.

Mixed indentation styles are invalid.

---

## Statement Termination

Statements terminate at newline boundaries.

Semicolons are forbidden.

---

# Type System

## Static Typing

Maple is statically typed.

All variable bindings and function signatures are type-checked at compile time.

---

## Mapleitive Types

```maple
i8 i16 i32 i64
u8 u16 u32 u64
f32 f64
bool
char
str
bytes
```

---

## Generic Containers

```maple
vec[T]
map[K V]
opt[T]
res[T E]
```

---

## Nil Semantics

`nil` exists but nullable-by-default types are discouraged.

Preferred:

```maple
let name opt[str]
```

Avoid:

```maple
let name str = nil
```

---

# Variables

## Immutable Variables

```maple
let x i32 = 10
```

---

## Mutable Variables

```maple
mut counter i32 = 0
```

---

# Functions

## Function Declaration

```maple
fun add(a i32, b i32) i32
    ret a + b
```

---

## Public Functions

```maple
pub fun main() i32
    ret 0
```

---

## Return Semantics

Functions use explicit `ret`.

Implicit returns are not supported.

---

# Type Declarations

## Struct-Like Types

```maple
type User
    name str
    age  i32
```

Maple does not include:

* classes
* inheritance
* prototypes

Methods are ordinary functions.

---

# Control Flow

## Conditionals

```maple
if score > 90
    grade = "A"
elif score > 80
    grade = "B"
else
    grade = "C"
```

---

## Infinite Loops

```maple
loop
    tick()
```

---

## Iteration

```maple
for item in items
    print(item)
```

---

## Loop Control

```maple
continue
esc
```

---

# Expressions

## Supported Operators

```text
+ - * / %
== !=
> < >= <=
&& ||
```

Custom operators are not supported.

---

# Functions Calls

Function calls require parentheses.

```maple
print(value)
```

---

# Memory Model

Maple targets low memory usage and deterministic execution.

Recommended runtime model:

* ownership-lite semantics
* arena allocation
* ARC-assisted resource management
* minimal runtime metadata

Tracing garbage collection is discouraged.

---

# Execution Model

## Initial Runtime Target

Register-based virtual machine.

Benefits:

* fast startup
* low memory overhead
* portable execution
* small runtime

---

## Future Backend

Optional:

* Cranelift JIT
* native AOT compilation

---

# Error Handling

Maple uses result-based error handling.

## Result Type

```maple
res[T E]
```

## Error Propagation

```maple
let file = fs.read("a.txt")?
```

---

# Formatting Rules

Maple formatting is canonical.

A formatter must produce:

* one deterministic output style
* stable indentation
* stable spacing
* stable AST layout

---

# Standard Library Philosophy

The standard library should remain:

* small
* orthogonal
* capability-oriented

## Initial Modules

```text
io
fs
net
json
time
proc
path
env
```

---

# Features Explicitly Excluded

The following are intentionally excluded from v0.1:

* classes
* inheritance
* macros
* traits
* async/await
* exceptions
* implicit coercions
* operator overloading
* multiple loop syntaxes
* optional braces
* semicolons
* borrow-checker complexity

---

# Example Program

```maple
use io

type User
    name str
    age  i32

fun greet(u User)
    io.println("hello " + u.name)

pub fun main() i32
    let user User = User(
        name: "edward"
        age: 20
    )

    greet(user)

    for n in [1, 2, 3]
        io.println(n)

    ret 0
```

---

# Language Identity

Maple is:

> A statically typed, indentation-sensitive, AI-native scripting language focused on deterministic syntax, low memory usage, fast execution, and reliable LLM code generation.

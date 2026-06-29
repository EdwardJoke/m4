# m4 Language Specification (Draft v0.3.2)

## Overview

m4 is a statically typed, AI-native scripting language designed for:

* fast execution
* low memory usage
* deterministic syntax
* canonical formatting
* high LLM generation reliability
* minimal grammar complexity

m4 emphasizes:

* explicitness
* predictable parsing
* low token usage
* stable AST generation
* minimal keywords

The language is indentation-sensitive and does not use `{}` block delimiters.

---

# Design Goals

## m4ary Goals

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

m4 does not use:

* `{`
* `}`
* semicolons

Blocks are defined by indentation only.

Example:

```m4
if x > 10
    std.println("large")
else
    std.println("small")
```

---

## 3. Explicit Types Preferred

Types should be written explicitly whenever practical.

Preferred:

```m4
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

m4 is limited to a maximum of 15 keywords.

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

m4 is statically typed.

All variable bindings and function signatures are type-checked at compile time.

---

## m4itive Types

```m4
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

```m4
vec[T]
map[K V]
opt[T]
res[T E]
```

---

## Nil Semantics

`nil` exists but nullable-by-default types are discouraged.

Preferred:

```m4
let name opt[str]
```

Avoid:

```m4
let name str = nil
```

---

# Variables

## Immutable Variables

```m4
let x i32 = 10
```

---

## Mutable Variables

```m4
mut counter i32 = 0
```

---

# Functions

## Function Declaration

```m4
fun add(a i32, b i32) i32
    ret a + b
```

---

## Public Functions

```m4
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

```m4
type User
    name str
    age  i32
```

m4 does not include:

* classes
* inheritance
* prototypes

Methods are ordinary functions.

---

# Control Flow

## Conditionals

```m4
if score > 90
    grade = "A"
elif score > 80
    grade = "B"
else
    grade = "C"
```

---

## Infinite Loops

```m4
loop
    tick()
```

---

## Iteration

```m4
for item in items
    print(item)
```

---

## Loop Control

```m4
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

```m4
print(value)
```

---

# Memory Model

m4 targets low memory usage and deterministic execution.

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

m4 uses result-based error handling.

## Result Type

```m4
res[T E]
```

## Error Propagation

```m4
let file = fs.read("a.txt")?
```

---

# Formatting Rules

m4 formatting is canonical.

A formatter must produce:

* one deterministic output style
* stable indentation
* stable spacing
* stable AST layout

---

# Standard Library Reference

The standard library provides a small set of orthogonal modules.
Each module is loaded explicitly via `use <module>`.

## `std` — Core I/O and Utilities

The `std` module provides basic input/output operations and utility functions.

```m4
use std
```

### `std.println(value)`

Print a value to stdout followed by a newline.

- **Parameters:** `value` — any type (int, float, bool, string, char, nil). Accepts multiple arguments.
- **Returns:** `nil`

```m4
std.println(42)            # 42
std.println("hello")       # hello
std.println(true)           # true
std.println(3.14)           # 3.14
std.println(1, 2, 3)        # 1 2 3  (multiple arguments)
std.println("line " + 1)    # line 1  (string concatenation)
```

### `std.print(value)`

Print a value to stdout without a trailing newline.

- **Parameters:** `value` — any type. Accepts multiple arguments.
- **Returns:** `nil`

```m4
std.print("hello ")
std.println("world")    # hello world (on one line)
```

### `std.readln()`

Read a line of text from stdin (up to the next newline).

- **Parameters:** none
- **Returns:** `str` — the line of text (excluding newline), or `nil` on error

```m4
let name = std.readln()
std.println("Hello, " + name)
```

### `std.read()`

Read all remaining data from stdin until EOF.

- **Parameters:** none
- **Returns:** `str` — all data read from stdin, or `nil` on error

```m4
let data = std.read()
std.println("Read " + str.len(data) + " bytes")
```

### `std.readChar()`

Read a single Unicode character from stdin.

- **Parameters:** none
- **Returns:** `char` — the character read (or `0` on EOF)

```m4
let ch = std.readChar()
std.println(ch)
```

### `std.range(start, end)`

Generate a vector of integers from `start` (inclusive) to `end` (exclusive).

This is identical to `range.range()`. Both are available for convenience.

- **Parameters:** `start i32`, `end i32`
- **Returns:** `vec[i32]`

```m4
for n in std.range(0, 5)
    std.println(n)       # 0, 1, 2, 3, 4
```

---

## `fs` — File System

The `fs` module provides basic file system operations.

```m4
use fs
```

### `fs.read(path)`

Read the entire contents of a file.

- **Parameters:** `path str` — path to the file
- **Returns:** `str` on success, `nil` on error (file not found, permission denied, etc.)

```m4
let content = fs.read("/tmp/data.txt")
if content != nil
    std.println(content)
```

### `fs.write(path, data)`

Write data to a file, overwriting if it exists.

- **Parameters:** `path str`, `data str`
- **Returns:** `bool` — `true` on success, `false` on error

```m4
let ok = fs.write("/tmp/output.txt", "Hello, file!")
if ok
    std.println("Write successful")
```

### `fs.exists(path)`

Check whether a file exists at the given path.

- **Parameters:** `path str`
- **Returns:** `bool`

```m4
if fs.exists("/tmp/data.txt")
    std.println("File exists")
```

### `fs.delete(path)`

Delete a file from the filesystem.

- **Parameters:** `path str`
- **Returns:** `bool` — `true` on success, `false` on error

```m4
let ok = fs.delete("/tmp/temp.txt")
if ok
    std.println("Deleted")
```

---

## `str` — String Utilities

The `str` module provides string introspection and manipulation.

```m4
use str
```

### `str.len(s)`

Return the byte length of a string.

- **Parameters:** `s str`
- **Returns:** `i32` — byte length (0 for empty string, 0 for non-string arguments)

```m4
let len = str.len("hello")    # 5
std.println(len)
```

### `str.slice(s, start, end)`

Extract a substring (byte-level slicing).

- **Parameters:** `s str`, `start i32`, `end i32`
- **Returns:** `str` on success, `nil` on error (out of bounds, negative indices, start > end)

```m4
let s = "hello"
let sub = str.slice(s, 0, 2)   # "he"
std.println(sub)

let sub2 = str.slice(s, 2, 5)  # "llo"
std.println(sub2)
```

---

## `thread` — Concurrency

The `thread` module provides thread spawning and message passing via channels.

```m4
use thread
```

### `thread.spawn(fun, ...)`

Spawn a function in a new thread. The function receives the provided arguments.

- **Parameters:** `fun` — a function (up to 8 arguments supported)
- **Returns:** handle (opaque vec) — pass to `thread.join()` to retrieve the result

```m4
fun compute(x i32) i32
    ret x * 2

let handle = thread.spawn(compute, 21)
let result = thread.join(handle)
std.println(result)     # 42
```

### `thread.join(handle)`

Join a spawned thread and retrieve its return value.

- **Parameters:** `handle` — the handle returned by `thread.spawn()`
- **Returns:** the return value of the spawned function

```m4
let handle = thread.spawn(my_func, 10, 20)
let result = thread.join(handle)
```

### `thread.channel()`

Create a new channel for sending values between threads (capacity: 64).

- **Parameters:** none
- **Returns:** channel (opaque vec)

```m4
let ch = thread.channel()
```

### `thread.send(channel, value)`

Send a value into a channel. Blocks if the channel is full.

- **Parameters:** `channel`, `value` — any type
- **Returns:** `bool` — `true` on success, `false` if channel is closed

```m4
let ok = thread.send(ch, 42)
```

### `thread.recv(channel)`

Receive a value from a channel. Blocks if the channel is empty.

- **Parameters:** `channel`
- **Returns:** the value sent through the channel, or `nil` if channel is closed and empty

```m4
let val = thread.recv(ch)
std.println(val)
```

**Example — Producer/Consumer Pattern:**

```m4
let ch = thread.channel()

thread.send(ch, 10)
thread.send(ch, 20)

let r1 = thread.recv(ch)   # 10
let r2 = thread.recv(ch)   # 20
```

---

## `range` — Range Generation

The `range` module generates numeric ranges as vectors.

```m4
use range
```

### `range.range(start, end)`

Generate a vector of integers from `start` (inclusive) to `end` (exclusive).

- **Parameters:** `start i32`, `end i32`
- **Returns:** `vec[i32]`

```m4
let nums = range.range(0, 3)   # [0, 1, 2]
for n in nums
    std.println(n)
```

---

# Standard Library Philosophy

The standard library should remain:

* small
* orthogonal
* capability-oriented

Planned future modules (`net`, `json`, `time`, `proc`, `path`, `env`) are not yet implemented.

---

# Error Codes Reference

All diagnostic errors use a structured code format: `[{code}] {Stage}: {message}`.
Codes are grouped by pipeline stage and can be looked up with `m4 explain <code>`.

## Parse Errors

| Code | Title | When it occurs |
|------|-------|----------------|
| `p001` | Syntax Error | Unexpected token, missing delimiter, or malformed expression |
| `p002` | Unexpected End of Input | Source ended prematurely (incomplete expression, unclosed block) |
| `p003` | Indentation Error | Indentation doesn't match any enclosing block |
| `p004` | Invalid Literal | A numeric literal (int or float) couldn't be parsed |

## Type Errors

| Code | Title | When it occurs |
|------|-------|----------------|
| `t001` | Type Mismatch | Value used in a context expecting a different type |
| `t002` | Undefined Variable | Variable referenced before declaration |
| `t003` | Duplicate Declaration | Same variable name declared twice in the same scope |
| `t004` | Type Mismatch in Binding | Assigned value doesn't match the variable's declared type |
| `t005` | Return Type Mismatch | `ret` value doesn't match the function's return type |
| `t006` | Arity Mismatch | Function called with wrong number of arguments |
| `t007` | Invalid Operator for Type | Operator used on unsupported types (e.g., arithmetic on booleans) |
| `t008` | Assignment to Immutable Variable | Trying to assign to a `let` variable (use `mut` instead) |
| `t009` | ret Outside Function | `ret` used outside of a `fun` block |

## Compile Errors

| Code | Title | When it occurs |
|------|-------|----------------|
| `c001` | Compile Error | Internal compiler error (unsupported construct or compiler limit) |
| `c002` | Continue Outside Loop | `continue` used outside a loop body |
| `c003` | Esc Outside Loop | `esc` used outside a loop body |
| `c004` | Too Many Constants | Constant table exceeded 65535 entries |
| `c005` | Too Many Locals | More than 256 local variables in a function |
| `c006` | Compile Error in Function | Error compiling a specific function body |

## Runtime Errors

| Code | Title | When it occurs |
|------|-------|----------------|
| `r001` | Undefined Variable | Global variable referenced before assignment |
| `r002` | Type Mismatch in Binary Operation | Binary operator applied to incompatible types |
| `r003` | Type Mismatch in Modulo | `%` applied to non-integer values |
| `r004` | Type Mismatch in Negation | `-` applied to non-numeric value |
| `r005` | Type Mismatch in Comparison | `>`, `<`, `>=`, `<=` applied to incompatible types |
| `r006` | Stack Overflow | Call stack exceeded 64 frames (infinite recursion) |
| `r007` | Value Not Callable | Non-function value used in a call expression |
| `r008` | Index Out of Bounds | Vector/string index outside valid range |
| `r009` | Not Indexable | Index operation applied to non-vector/non-string |
| `r010` | Nil Propagation | Nil value unwrapped with `!` operator |
| `r011` | Unknown Opcode | VM encountered unrecognized bytecode instruction |
| `r012` | Division by Zero | Division where divisor is zero |
| `r013` | Modulo by Zero | Modulo where divisor is zero |
| `r014` | Out of Memory | Allocator failed to allocate memory |
| `r015` | Invalid Argument | Native function received wrong argument type |
| `r016` | I/O Error | Input/output operation failed (broken pipe, permission denied, etc.) |

## Using Error Codes

```bash
# Look up an error code's description
m4 explain r006

# Get structured output
m4 explain t001 --format json
m4 explain p002 --format yaml
```

---

# Features Explicitly Excluded

The following are intentionally excluded from v0.2:

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

```m4
use std

type User
    name str
    age  i32

fun greet(u User)
    std.println("hello " + u.name)

pub fun main() i32
    let user User = User(
        name: "edward"
        age: 20
    )

    greet(user)

    for n in [1, 2, 3]
        std.println(n)

    ret 0
```

---

# Language Identity

m4 is:

> A statically typed, indentation-sensitive, AI-native scripting language focused on deterministic syntax, low memory usage, fast execution, and reliable LLM code generation.

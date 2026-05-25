# Maple

> A statically typed, indentation-sensitive, AI-native scripting language focused on deterministic syntax, low memory usage, fast execution, and reliable LLM code generation.

Maple is a minimal scripting language implemented in Zig, featuring a hand-written scanner, recursive-descent Pratt parser, single-pass bytecode compiler, type checker, and a register-based virtual machine. It is designed from the ground up for low token usage, canonical formatting, and high LLM generation reliability.

## Features

- **Statically typed** — type checking at compile time with a rich type system (primitives, generics, option/result types)
- **Indentation-sensitive** — no braces, no semicolons; blocks are defined by indentation (like Python)
- **Register-based VM** — fast startup, low memory overhead, portable execution
- **Single-pass bytecode compiler** — compiles directly from the AST to bytecode in one pass
- **Pratt parser** — clean, extensible expression parsing with operator precedence
- **REPL** — interactive mode for quick experimentation
- **Canonical formatting** — one deterministic output style per construct
- **15 keywords only** — minimal grammar, minimal syntax entropy
- **Result-based error handling** — `res[T E]` type with `?` propagation operator
- **Structured error output** — diagnostics in ZON, JSON, or YAML formats

## Quick Start

### Prerequisites

- [Zig](https://ziglang.org/download/) 0.16.0 or later

### Build

```sh
zig build
```

The binary is placed at `zig-out/bin/maple`.

### Run

```sh
# Launch REPL
zig build run

# Run a file
zig build run -- hello.maple

# Run from stdin
echo 'io.println(42)' | zig build run -- -

# Or build and use the binary directly
zig build
./zig-out/bin/maple hello.maple
```

## CLI

```
Maple v0.1.0 — statically typed, AI-native scripting language

Usage:
  maple [flags] <file.maple>   Run file
  maple [flags] -              Run from stdin
  maple                        Launch REPL

Flags:
  -d, --debug                  Show bytecode before execution
  --check                      Parse and type-check only
  -f, --format                 Pretty-print source
  --error-format=zon|json|yaml Structured error output format
  -h, --help                   Show this help
  -v, --version                Show version
```

## Language Overview

### Keywords (15 total)

| Keyword    | Purpose                 |
| ---------- | ----------------------- |
| `let`      | immutable variable      |
| `mut`      | mutable variable        |
| `fun`      | function declaration    |
| `pub`      | public declaration      |
| `if`       | conditional             |
| `elif`     | alternative conditional |
| `else`     | fallback conditional    |
| `loop`     | infinite loop           |
| `for`      | iteration               |
| `continue` | loop continuation       |
| `esc`      | loop exit               |
| `ret`      | return                  |
| `nil`      | null value              |
| `use`      | module import           |
| `type`     | type declaration        |

### Example Program

```maple
use io

type User
    name str
    age  i32

fun greet(u User)
    io.println("hello " + u.name)

pub fun main()
    let user User = User(
        name: "edward"
        age: 20
    )

    greet(user)

    for n in [1, 2, 3]
        io.println(n)
```

### Variables

```maple
let x i32 = 10          # immutable, type annotation
mut counter i32 = 0     # mutable
let pi = 3.14           # type inference
```

### Functions

```maple
fun add(a i32, b i32) i32
    ret a + b
```

### Control Flow

```maple
if score > 90
    grade = "A"
elif score > 80
    grade = "B"
else
    grade = "C"

loop
    tick()

for item in items
    print(item)
```

### Types

**Primitives:** `i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool char str bytes`

**Containers:** `vec[T] map[K V] opt[T] res[T E]`

## Project Structure

```
src/
├── main.zig          — Entry point
├── cli.zig           — CLI flag parsing, REPL, file execution
├── scanner.zig       — Hand-written lexer with indentation tracking
├── token.zig         — Token types and keyword definitions
├── ast.zig           — AST node definitions and arena allocator
├── parser.zig        — Recursive-descent Pratt parser
├── compiler.zig      — Single-pass bytecode compiler
├── vm.zig            — Register-based virtual machine
├── opcode.zig        — Bytecode instruction encoding/decoding
├── chunk.zig         — Chunk of bytecode (code + constants + lines)
├── value.zig         — Runtime value representation
├── object.zig        — Heap-allocated objects (functions, structs, vecs)
├── type.zig          — Type system definitions
├── type_check.zig    — Type checker with scope-chain environments
├── fmt.zig           — Canonical AST pretty-printer
├── debug.zig         — Bytecode disassembler
├── error.zig         — Structured diagnostic system (ZON/JSON/YAML)
├── root.zig          — Module root re-exporting public declarations
└── stdlib/
    └── io.zig        — Standard I/O native functions (print, println)
```

## Status

Maple is in **early development** (v0.1.0). The core pipeline (scan → parse → type-check → compile → execute) is functional, but the language and runtime are minimal. Expect significant changes and additions.

### Implemented
- Scanner, parser, AST, compiler, VM, type checker
- REPL and file execution
- Integers, floats, booleans, strings, nil, chars
- Variables (`let`, `mut`), functions (`fun`), conditionals (`if`/`elif`/`else`)
- Loops (`loop`, `for`), loop control (`continue`, `esc`)
- String concatenation, arithmetic, comparison, logical operators
- `io.println` / `io.print` native functions
- Struct literals with named fields
- Vectors (list literals, indexing, iteration)
- Error propagation with `?`
- Canonical formatter
- Bytecode disassembler
- Structured diagnostics (ZON, JSON, YAML)

### Not Yet Implemented
- Full standard library (`fs`, `net`, `json`, `time`, etc.)
- Result type runtime support
- Modules beyond `io`
- AOT compilation / Cranelift JIT backend
- Ownership-lite memory model
- Package manager

## License

MIT

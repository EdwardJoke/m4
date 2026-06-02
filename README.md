# m4

> A statically typed, indentation-sensitive, AI-native scripting language focused on deterministic syntax, low memory usage, fast execution, and reliable LLM code generation.

m4 is a minimal scripting language implemented in Zig, featuring a hand-written scanner, recursive-descent Pratt parser, single-pass bytecode compiler, type checker, and a register-based virtual machine. It is designed from the ground up for low token usage, canonical formatting, and high LLM generation reliability.

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

The binary is placed at `zig-out/bin/m4`.

### Run

```sh
# Launch REPL
zig build run

# Run a file
zig build run -- hello.m4

# Run from stdin
echo 'io.println(42)' | zig build run -- -

# Or build and use the binary directly
zig build
./zig-out/bin/m4 hello.m4
```

## CLI

```
m4 v0.2.1 — statically typed, AI-native scripting language

Usage:
  m4 [flags] <file.m4>          Run file
  m4 [flags] -                  Run from stdin
  m4                            Launch REPL

Commands:
  m4 help [--zon|--json|--yaml]   Show this help
  m4 version [--zon|--json|--yaml] Show version
  m4 lint <file.m4>               Parse and type-check only
  m4 build <file.m4> [opts]       Compile to native binary
  m4 explain <code>               Explain an error code

Use 'm4 <command> help' for command-specific help (e.g. 'm4 lint help --zon').

Flags:
  -d, --debug                    Show bytecode before execution
  -f, --format                   Format source code and print
  --native                       Emit QBE IR instead of running via bytecode VM
  --zon, --json, --yaml           Structured error output format

Build options:
  -o, --output <path>            Output binary path (default: <file>.out)
  -target, --target <arch>       Target architecture (amd64_apple, arm64_apple, arm64, amd64_sysv, rv64)
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

```m4
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

```m4
let x i32 = 10          # immutable, type annotation
mut counter i32 = 0     # mutable
let pi = 3.14           # type inference
```

### Functions

```m4
fun add(a i32, b i32) i32
    ret a + b
```

### Control Flow

```m4
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
    ├── qbe.zig          — QBE IR emitter for native compilation
    ├── qbe_build.zig    — QBE native binary build pipeline
    ├── runtime/
    │   ├── m4rt.c       — Minimal C runtime for native-compiled programs
    │   ├── m4rt.h       — Runtime header with type definitions
    │   ├── qbe_wrap.c   — QBE C API wrapper
    │   └── qbe_wrap.h   — QBE wrapper header
    └── stdlib/
        ├── io.zig       — Standard I/O (print, println, readln, read, readChar)
        ├── std.zig      — Core stdlib (println, print, readln, read, range)
        ├── thread.zig   — Threading primitives (spawn, join, channel, send, recv)
        └── range.zig    — Numeric range generator
```

## Status

m4 is in **early development** (v0.2.1). The core pipeline (scan → parse → type-check → compile → execute) is functional, with a QBE native compilation backend. Expect significant changes and additions.

### Implemented
- Scanner, parser, AST, compiler, VM, type checker
- REPL and file execution
- Integers, floats, booleans, strings, nil, chars
- Variables (`let`, `mut`), functions (`fun`), conditionals (`if`/`elif`/`else`)
- Loops (`loop`, `for`), loop control (`continue`, `esc`)
- String concat, comparison, indexing, length
- Arithmetic, comparison, logical operators
- `io.println` / `io.print` / `io.readln` / `io.read` / `io.readChar`
- `std.println` / `std.print` / `std.readln` / `std.read` / `std.range`
- `thread.spawn` / `thread.join` / channels
- `range.range` — numeric range generator
- Struct literals with named fields
- Vectors (list literals, indexing, iteration)
- Error propagation with `?`
- Canonical formatter
- Bytecode disassembler
- Structured diagnostics (ZON, JSON, YAML)
- Error code explainer (`m4 explain r001`)
- QBE backend: IR emitter and native binary pipeline (in development)
- Benchmarks vs Python/TypeScript

### Not Yet Implemented
- Full standard library (`fs`, `net`, `json`, `time`, etc.)
- Result type runtime support
- Modules beyond `std` / `io` / `thread` / `range`
- Cranelift JIT backend
- Ownership-lite memory model
- Package manager

## License

MIT

## Thanks

This project is built on open-source projects:

Thanks [QBE](https://c9x.me/compile/) compiler backend.

Thanks [Zig](https://ziglang.org/).

Thanks [serde.zig](https://github.com/OrlovEvgeny/serde.zig).

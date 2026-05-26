# AGENTS.md — m4 Language

## What is m4?

**m4** is a statically typed, indentation-sensitive, AI-native scripting language focused on deterministic syntax, low memory usage, fast execution, and reliable LLM code generation. It is designed from the ground up for low token usage, canonical formatting, and high LLM generation reliability.

The language uses 15 keywords, no braces, no semicolons — blocks are defined by indentation (like Python). It features result-based error handling (`res[T E]`), generic containers (`vec[T]`, `map[K V]`, `opt[T]`, `res[T E]`), and a register-based virtual machine.

**Status:** Early development (v0.1.2). Core pipeline (scan → parse → type-check → compile → execute) is functional. Significant changes expected.

---

## Dev Stack

| Layer              | Technology                                              |
| ------------------ | ------------------------------------------------------- |
| Language           | Zig 0.16.0+                                             |
| Build system       | `build.zig` + `build.zig.zon`                           |
| External deps      | `serde.zig` (ZON/JSON/YAML serialization)               |
| Test framework     | Zig built-in `test` blocks + `zig build test`           |
| Target             | Native (any OS/arch supported by Zig)                   |
| Minimum Zig        | 0.16.0                                                  |

---

## Architecture Overview

m4 follows a classic language pipeline:

```
source → Scanner → tokens → Parser → AST → Type Checker → Compiler → bytecode → VM
```

### Pipeline Stages

1. **Scanner** (`src/scanner.zig`) — Hand-written lexer with indentation tracking. Emits tokens including `INDENT`/`DEDENT`/`NEWLINE`. Supports parenthesis-depth tracking to suppress indentation inside `(...)`.

2. **Parser** (`src/parser.zig`) — Recursive-descent Pratt parser. Produces a flat-indexed AST via `NodeArena`. Handles all declarations (`let`, `mut`, `fun`, `pub`, `type`, `use`) and statements (`if`/`elif`/`else`, `loop`, `for`, `continue`, `esc`, `ret`, expressions).

3. **Type Checker** (`src/type_check.zig`) — Scope-chain environment checker. Two-pass: collects type declarations first, then checks all statements. Supports primitive types, generics (`vec`, `map`, `opt`, `res`), function types, and user-defined struct types.

4. **Compiler** (`src/compiler.zig`) — Single-pass bytecode compiler. Translates AST nodes directly into register-based bytecode instructions. Compiles function bodies into separate `Chunk`s with their own register allocators.

5. **VM** (`src/vm.zig`) — Register-based virtual machine. 256 registers, 64 call frames. Inline fast-paths for int-int arithmetic and comparisons. Global value cache for hot lookups. Dispatches native functions via function pointer table.

### Key Source Files

| File                     | Purpose                                                       |
| ------------------------ | ------------------------------------------------------------- |
| `src/main.zig`           | Entry point                                                   |
| `src/cli.zig`            | CLI: flags, REPL, file execution, stdin mode, `explain` cmd  |
| `src/scanner.zig`        | Hand-written lexer with indentation tracking                  |
| `src/token.zig`          | Token types + keyword registry (15 keywords + 2 bool literals) |
| `src/ast.zig`            | AST node types (`Node` union) + `NodeArena` flat allocator    |
| `src/parser.zig`         | Pratt parser; handles struct literals via uppercase heuristic |
| `src/type.zig`           | Type system definitions + `parseTypeName` primitive lookup   |
| `src/type_check.zig`     | Scope-chain type checker                                      |
| `src/compiler.zig`       | Single-pass bytecode compiler                                 |
| `src/vm.zig`             | Register-based VM with call frames, native fn dispatch        |
| `src/opcode.zig`         | Bytecode instruction formats (iABC/iABx/iAsBx/iAx) + encode/decode |
| `src/chunk.zig`          | Bytecode chunk: code array + constant table + line info       |
| `src/value.zig`          | Runtime value representation (tagged union)                   |
| `src/object.zig`         | Heap-allocated objects: `FunObj`, `VecObj`, `MapObj`, `StructObj` |
| `src/debug.zig`          | Bytecode disassembler                                         |
| `src/fmt.zig`            | Canonical AST pretty-printer                                  |
| `src/error.zig`          | Structured diagnostics (ZON/JSON/YAML) + error code registry  |
| `src/root.zig`           | Module root: re-exports all public declarations               |
| `src/stdlib/std.zig`     | `std.println`, `std.print`, `std.readln`, `std.read`, `std.range` |
| `src/stdlib/io.zig`      | `io.println`, `io.print`, `io.readln`, `io.read`, `io.readChar` |
| `src/stdlib/thread.zig`  | `thread.spawn`, `thread.join`, `thread.channel`, `thread.send`, `thread.recv` |
| `src/stdlib/range.zig`   | `range.range` — numeric range generator                       |

---

## Build & Run

```sh
# Build the binary
zig build

# Run tests
zig build test

# Run the REPL
zig build run

# Run a file
zig build run -- hello.m4

# Run from stdin
echo 'std.println(42)' | zig build run -- -

# Check only (parse + type-check)
zig build run -- --check file.m4

# Show bytecode
zig build run -- -d file.m4
```

---

## Contribute Rules

### Code Style

- Follow Zig's standard style: 4-space indentation, snake_case for functions/variables, PascalCase for types.
- Keep the language minimal — no optional syntax, no operator overloading, no implicit coercions.
- Every new feature must maintain or reduce the keyword count (hard limit: 15 keywords).
- All compiler/VM additions must be tested with Zig's `test` blocks.
- Run `zig build test` before submitting changes.
- Ensure all examples in `examples/` still produce correct output.
- Do not break the `--check` (type-check-only) or `--format` (pretty-print) flags.

### Architecture Principles

1. **No semicolons, no braces** — the language is indentation-sensitive. Keep it that way.
2. **Canonical formatting** — there is exactly one way to format each construct. The `fmt.zig` AST pretty-printer defines the canonical form.
3. **AI-native** — design for LLM code generation. Low token entropy, predictable parsing, stable AST output.
4. **Single-pass compiler** — the compiler traverses the AST once. No intermediate representations.
5. **Register-based VM** — keep the VM simple. Inline fast paths for common operations (int arithmetic). Avoid tracing GC.
6. **Error handling** — use result-based errors (`res[T E]` with `?` propagation). No exceptions.

### Pull Request Process

- Update `SPEC.md` if the language grammar or type system changes.
- Update `README.md` if CLI flags or project structure changes.
- Add or update examples in `examples/` for new language features.
- Update `CHANGELOG.md` (in `.wasup/changelogs/`) following Keep a Changelog format.
- Bump the version in `build.zig.zon` following semver.

### Testing

- Unit tests live inline in each source file using Zig's `test` block syntax.
- Run all tests: `zig build test`
- For benchmarking, see `tests/` directory (m4 vs Python vs TypeScript speed comparison).
- The `--check` flag should always work: `zig build run -- --check file.m4`

### Error Code Registry

All error codes are defined in `src/error.zig` in the `ERROR_DB` array. When adding new error conditions, add an entry with a unique code following the naming convention:

- `pXXX` — parse errors
- `tXXX` — type errors
- `cXXX` — compile errors
- `rXXX` — runtime errors

---

## Language Design Principles

From `SPEC.md`:

1. **One Obvious Syntax** — every construct has one preferred representation, one parse path, one canonical format. Syntax aliases are forbidden.
2. **Indentation Defines Blocks** — no `{}`, no semicolons.
3. **Explicit Types Preferred** — types should be written explicitly whenever practical, especially in public APIs.
4. **Minimal Grammar Entropy** — avoid optional syntax forms, context-sensitive parsing, symbolic DSL patterns, and operator overloading.
5. **15 Keyword Limit** — the grammar is hard-limited to 15 keywords.
6. **Small Standard Library** — orthogonal, capability-oriented modules.

### Explicitly Excluded

- Classes, inheritance, traits
- Macros, async/await
- Exceptions, implicit coercions
- Operator overloading
- Multiple loop syntaxes
- Optional braces, semicolons
- Borrow-checker complexity
- Tracing garbage collection

---

## Current State (v0.1.2)

### Implemented
- Scanner, parser, AST, compiler, VM, type checker
- REPL and file execution
- Integers, floats, booleans, strings, nil, chars
- Variables (`let`, `mut`), functions (`fun`), conditionals (`if`/`elif`/`else`)
- Loops (`loop`, `for`), loop control (`continue`, `esc`)
- String concatenation, arithmetic, comparison, logical operators
- `std.println` / `std.print` / `std.range` native functions
- Struct literals with named fields
- Vectors (list literals, indexing, iteration)
- Error propagation with `?`
- Canonical formatter
- Bytecode disassembler
- Structured diagnostics (ZON, JSON, YAML)
- Error code explainer (`m4 explain r001`)
- Threading primitives (`thread.spawn`, `thread.join`, channels)
- Benchmarks vs Python/TypeScript

### Not Yet Implemented
- Full standard library (`fs`, `net`, `json`, `time`, etc.)
- Result type runtime support
- Modules beyond `std` / `io` / `thread` / `range`
- AOT compilation / Cranelift JIT backend
- Ownership-lite memory model
- Package manager

# ROADMAP — m4 Self-Hosting Compiler

> **Goal:** Write the m4 compiler in m4 itself. The Zig-hosted compiler bootstraps the process; once the m4-written compiler can compile itself, the bootstrap is complete.

---

## Current State (v0.2.0)

The m4 compiler lives entirely in Zig across ~4,500 lines of source. The pipeline is:

```
source → Scanner → tokens → Parser → AST → Type Checker → Compiler → bytecode → VM
```

| Stage     | File               | Zig LoC |
|-----------|---------------------|---------|
| Scanner   | `src/scanner.zig`  | ~280    |
| Parser    | `src/parser.zig`   | ~550    |
| Type Checker | `src/type_check.zig` | ~420 |
| Compiler  | `src/compiler.zig` | ~700    |
| VM        | `src/vm.zig`       | ~750    |
| Support   | opcode, chunk, ast, type, value, object, error, fmt, debug, token | ~1,800 |
| **Total** |                     | **~4,500** |

The language implements 15 keywords, indentation-sensitive blocks, Pratt parsing, a register-based bytecode VM, and a scope-chain type checker. String operations (concat, comparison, indexing, length) were recently added.

**The compiler can emit QBE SSA IR as an alternative backend path (v0.2.0), producing native binaries via QBE's code generator.** The bytecode VM path remains the primary execution mode. This is both a strength (simplicity) and a constraint (the self-hosted compiler must re-implement every stage).

---

## Phases

### Phase 0: Language Maturity (v0.2.x–v0.4.x)

Before the compiler can be written in m4, the language itself must be capable of expressing the compiler's logic. The current language is too minimal.

#### P0.1 — String & Byte Manipulation

- [x] String concatenation (`+`)
- [x] String comparison (`==`, `!=`, `<`, `>`, `<=`, `>=`)
- [x] String indexing (`s[i]`)
- [x] String length (`len(s)`)
- [ ] String slicing (`s[start:end]`)
- [ ] String escape sequences (already in scanner, verify completeness)
- [ ] Escape/unescape helpers (needed for lexing string literals in the self-hosted scanner)

#### P0.2 — Standard Library Essentials

- [ ] `std.ord(c)` — char to integer codepoint
- [ ] `std.chr(i)` — integer to char
- [ ] `std.to_string(i)` / `std.to_string(f)` — number to string
- [ ] `std.from_string(str)` — string to integer
- [ ] `str.ends_with`, `str.starts_with`, `str.contains`
- [ ] `str.trim`, `str.split`, `str.join`
- [ ] `fs.read(path)` — file I/O for reading source files
- [ ] `fs.write(path, data)` — file I/O for writing output
- [ ] `std.env.args()` — access CLI arguments

Without file I/O and robust string operations, the self-hosted compiler cannot read source files or produce output.

#### P0.3 — Data Structures for Compiler Internals

- [ ] `vec` type complete and stable (indexing, iteration, push/append)
- [ ] `map[K, V]` type with full support (insert, lookup, iteration)
- [ ] `opt[T]` with `?` propagation working in all contexts
- [ ] `res[T, E]` with `?` propagation working and runtime support
- [ ] User-defined `type` (struct) with field access and construction

The compiler needs maps for symbol tables, vectors for token streams and AST nodes, and structs for AST node types.

#### P0.4 — Compiler-Necessary Features

- [ ] Recursion (functions calling themselves, mutual recursion)
- [ ] Stable struct field access (`obj.field` syntax)
- [ ] Nested function calls with complex argument passing
- [ ] Bitwise operations (not strictly required, but useful for opcode encoding)
- [ ] `assert(condition)` built-in for test framework

---

### Phase 1: m4-in-m4 Prototype (v0.5.x)

Write a self-hosted compiler **in m4** that compiles a **strict subset** of the language. This prototype proves the approach and exposes missing language features.

#### 1.1 — Scanner in m4

Write `scanner.m4` — a hand-written lexer in m4 that:

- Consumes source text character-by-character
- Handles indentation tracking (INDENT/DEDENT/NEWLINE)
- Skips comments (`#`)
- Identifies keywords (15 keywords + 2 bool literals)
- Identifies operators, numbers, strings, identifiers
- Emits a `vec[Token]`

**Deliverable:** A pure-m4 scanner that produces the same token stream as `src/scanner.zig`.

*Estimated size:* ~300–400 lines of m4.

#### 1.2 — Parser in m4

Write `parser.m4` — a recursive-descent Pratt parser in m4 that:

- Consumes tokens from the scanner
- Builds a flat-indexed `vec[Node]` (equivalent to `NodeArena`)
- Handles all declaration types (`let`, `mut`, `fun`, `pub`, `type`, `use`)
- Handles all statement types (`if`/`elif`/`else`, `loop`, `for`, `continue`, `esc`, `ret`)
- Handles all expression types (binary, unary, calls, literals, field access, indexing)
- Handles struct literals via the uppercase heuristic

**Deliverable:** A pure-m4 parser that produces the same AST as `src/parser.zig`.

*Estimated size:* ~500–600 lines of m4.

#### 1.3 — Type Checker in m4

Write `type_check.m4` — a scope-chain type checker in m4 that:

- Manages `TypeEnv` objects (parent-linked symbol tables)
- Supports all primitive types, generics (`vec`, `map`, `opt`, `res`), function types, user-defined structs
- Validates expressions, assignments, function calls, return types
- Reports structured type errors

**Deliverable:** A pure-m4 type checker that validates the same programs as `src/type_check.zig`.

*Estimated size:* ~400–500 lines of m4.

#### 1.4 — Bytecode Compiler in m4

Write `compiler.m4` — a single-pass bytecode compiler in m4 that:

- Walks the AST and emits opcodes into a `Chunk` structure
- Manages register allocation (local variables, temporaries)
- Handles control flow (if/elif/else, loop, for, continue, esc)
- Handles function compilation with separate chunks
- Handles struct/vec literal compilation
- Produces the same bytecode as `src/compiler.zig`

**Deliverable:** A pure-m4 compiler that produces bytecode chunks.

*Estimated size:* ~700–800 lines of m4.

#### 1.5 — VM in m4

Write `vm.m4` — a register-based virtual machine in m4 that:

- Interprets bytecode from a `Chunk`
- Implements all opcodes (arithmetic, comparison, jumps, calls, returns, struct/vec ops)
- Manages call frames and recursion
- Handles native function dispatch
- Provides runtime error messages

This is the **largest and most performance-critical** piece. The m4 VM running in the Zig-hosted VM will be significantly slower than the native Zig VM.

**Deliverable:** A pure-m4 bytecode interpreter.

*Estimated size:* ~800–1,000 lines of m4.

#### 1.6 — Integration & Testing

- [ ] Wire the m4-written compiler stages together
- [ ] Test against all existing `examples/*.m4`
- [ ] Test against the hardspeed benchmarks
- [ ] Verify bytecode output matches the Zig compiler's output
- [ ] Fix bugs and missing features exposed by the prototype

---

### Phase 2: Bootstrap (v0.6.x)

This is where self-hosting actually happens.

```
┌──────────────────────────────────────────────────────────┐
│  Bootstrap Chain                                          │
│                                                          │
│  Step 1:  m4  (v0.5)  ───compiles──→  m4c-bootstrap    │
│             ↑                        (binary #1)         │
│         (Zig compiler)                                    │
│                                                          │
│  Step 2:  m4c-bootstrap  ───compiles──→  m4c-v1          │
│             ↑                        (binary #2)         │
│         (compiler source .m4)                             │
│                                                          │
│  Step 3:  m4c-bootstrap  ───compiles──→  m4c-v2          │
│             ↑                        (binary #3)         │
│         (compiler source .m4)                             │
│         (binary #2 == binary #3 means success!)           │
└──────────────────────────────────────────────────────────┘
```

#### 2.1 — Bootstrap Compiler Binary

- [ ] Compile the full m4-written compiler (`scanner.m4` + `parser.m4` + `type_check.m4` + `compiler.m4` + `vm.m4`) using the Zig-hosted m4 compiler
- [ ] This produces `m4c-bootstrap` — the first binary of the m4-written compiler

#### 2.2 — Second-Stage Compilation

- [ ] Run `m4c-bootstrap` to compile the same m4-written compiler source
- [ ] This produces `m4c-v1` — a binary compiled by the m4-written compiler

#### 2.3 — Third-Stage Verification

- [ ] Run `m4c-bootstrap` again to compile the compiler source → `m4c-v2`
- [ ] **The bootstrap is complete when `m4c-v1` and `m4c-v2` are byte-identical** (or produce identical behavior)
- [ ] This proves the m4-written compiler can compile itself

#### 2.4 — Continuous Integration

- [ ] Add CI pipeline that verifies bootstrap integrity on every commit
- [ ] Track performance regressions (self-hosted compilation time)

---

### Phase 3: Production Self-Hosting (v0.7.x)

#### 3.1 — Performance Optimization

The self-hosted compiler running inside the Zig VM will be ~10–100× slower than the native Zig compiler. Optimizations:

- [ ] Profile the m4-written compiler to find hot spots
- [ ] Optimize critical loops (character scanning, AST traversal)
- [ ] Add compiler intrinsics for hot paths (e.g., `__builtin_char_at`)
- [ ] Reduce allocator pressure in the VM (arena reuse)
- [ ] JIT compilation via QBE backend (v0.2.0 work)

#### 3.2 — Full Feature Parity

- [ ] Ensure the m4-written compiler supports every language feature in `SPEC.md`
- [ ] Pass all existing test suites
- [ ] Pass all examples

#### 3.3 — Replace the Zig Compiler

- [ ] The Zig compiler becomes the bootstrap seed only
- [ ] New developer setup: `git clone → zig build → m4 compiler.m4 → m4c`
- [ ] The m4-written compiler is the primary implementation
- [ ] Zig code is only maintained for bootstrapping and the VM runtime

---

### Phase 4: Full Independence (v1.0+)

#### 4.1 — Drop the Zig VM Runtime

- [ ] Implement a minimal runtime in C (~500 lines) for the self-hosted compiler
- [ ] Or use the QBE backend to compile to native code directly
- [ ] The Zig bootstrap reduces to just enough code to compile the m4-written scanner

#### 4.2 — Self-Hosted Standard Library

- [ ] Port all stdlib modules (`io.zig`, `std.zig`, `thread.zig`, `range.zig`) from Zig to m4
- [ ] The m4-written compiler compiles the m4-written stdlib

#### 4.3 — Self-Hosted Language Tooling

- [ ] Formatter (`fmt.m4`) — port of `src/fmt.zig`
- [ ] Bytecode disassembler (`debug.m4`) — port of `src/debug.zig`
- [ ] Linter / static analyzer in m4
- [ ] Language server protocol (LSP) server in m4

#### 4.4 — Drop the Zig Bootstrap Entirely

- [ ] Store a pre-compiled bytecode image of the m4 compiler as the seed
- [ ] New developer setup: `run m4c-seed compiler.m4 → m4c`
- [ ] The Zig codebase becomes optional documentation only

---

## Success Criteria

1. **Phase 1 complete:** All five compiler stages are implemented in m4 and pass the example suite
2. **Phase 2 complete:** `m4c-v1 == m4c-v2` (the compiler compiles itself identically)
3. **Phase 3 complete:** The m4-written compiler is the primary implementation used in CI
4. **Phase 4 complete:** No Zig code required to build the m4 compiler

---

## Key Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| **Performance:** m4 running on the Zig VM may be too slow to compile large files | Start with small files; profile before optimizing; add intrinsics for hot paths |
| **Bugs in m4 language:** Uncovered while writing the compiler in m4 itself | Fix aggressively; add tests for each bug found; the compiler-writing process validates the language |
| **Feature creep:** The language keeps growing, making self-hosting a moving target | Stabilize the language spec at v0.5.0 before starting the m4 compiler; freeze the spec during bootstrap |
| **VM limitations:** 256 registers, 64 frames may not be enough for a complex compiler | Raise limits if needed; the compiler is a compile-time tool, not a production runtime |
| **Bootstrap chicken-and-egg:** Need feature X to implement the compiler, but feature X isn't in m4 yet | Implement feature X in Zig first; then port to m4 once the feature exists |

---

## Timeline Estimate

| Phase | Version | Effort | Description |
|-------|---------|--------|-------------|
| P0    | v0.2–v0.4 | 2–4 months | Language maturity & stdlib |
| P1    | v0.5      | 2–3 months | m4-in-m4 prototype |
| P2    | v0.6      | 1 month   | Bootstrap |
| P3    | v0.7      | 2–3 months | Production self-hosting |
| P4    | v1.0+     | 2–4 months | Full independence |

Total estimated time to v1.0: **9–15 months** depending on contributor velocity.

---

## How to Contribute

1. Start with **Phase 0** — build out the m4 standard library and stabilize the language
2. Read the full Zig compiler source (`src/scanner.zig` → `src/parser.zig` → `src/type_check.zig` → `src/compiler.zig` → `src/vm.zig`)
3. Implement the scanner in m4 first — it's the smallest and most self-contained stage
4. Test against the existing examples after each stage
5. Do not attempt bootstrap until the entire pipeline produces identical output to the Zig compiler

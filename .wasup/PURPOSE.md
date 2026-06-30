# v0.3.3 Purpose

## What
Bug-fix release focusing on runtime memory management, QBE backend correctness, parser diagnostics, stdlib cleanup, and test runner stability.

## Why
Address accumulated technical debt and correctness issues discovered during v0.3.2 development. Fix runtime memory leaks, QBE backend state leaks, parser error propagation, and stdlib API issues.

## Success Criteria
- [ ] M1: Fix runtime memory management — shallow teardown in m4_free_value, correct signature, nil-safe div_u/mod_u
- [ ] M2: Fix qbe_wrap — reset opt before each compilation
- [ ] M3: Fix QBE backend — track BoxKind instead of bool in ensureBoxed
- [ ] M4: Fix qbe_build — hash-based runtime object cache
- [ ] M5: Fix parser — structured diagnostics for lex errors
- [ ] M6: Fix CLI — improve lint error format
- [ ] M7: Fix thread — dedicated Value tags for thread_handle and channel
- [ ] M8: Fix stdlib — resolve @constCast warnings, fix stringBuilder leak
- [ ] M9: Fix test runner — stable exit code, script portability

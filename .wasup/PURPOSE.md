# v0.3.2 Purpose

## What
Add `-D` flag to m4 CLI to pass QBE optimization levels, and optimize QBE backend with unboxed integer representation.

## Why
Expose QBE's optimization levels to m4 users, and eliminate heap allocation overhead for integer operations in the QBE native backend by using unboxed ints with native QBE arithmetic ops.

## Success Criteria
- [x] CLI accepts `-D` flag and passes it to QBE backend
- [x] Both `-Dfast` and `-Dsmall` modes produce valid, runnable binaries
- [x] Help text (`m4 --help`) documents the `-D` option with fast/small descriptions
- [x] Integer literals emit native QBE `copy` instead of `call $m4_new_int`
- [x] Binary arithmetic emits native QBE ops (`add`/`sub`/`mul`/`div`) instead of runtime calls
- [x] All existing tests pass with both bytecode VM and QBE native backend

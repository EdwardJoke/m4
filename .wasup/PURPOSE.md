# v0.3.1 Purpose

## What
Fix all 3 open bugs: integer overflow semantics, backwards LRU cache, and memory management for heap-allocated objects.

## Why
All three issues cause incorrect or inconsistent runtime behavior. Integer overflow makes programs behave differently across build modes. The backwards LRU cache provides negligible performance benefit. The complete lack of memory management makes long-running programs and native binaries unusable.

## Success Criteria
- [ ] Integer arithmetic has defined overflow semantics (wrap or error) consistent across all build modes
- [ ] Global value cache properly promotes hot entries and achieves meaningful hit rates
- [ ] Heap-allocated objects are freed — no leaks in VM, compiler, stdlib, or QBE runtime

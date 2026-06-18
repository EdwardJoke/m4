# v0.2.2 Purpose

## What
Ship v0.2.2 stable from rc1 with comprehensive speed tests, performance benchmarking, compute usage profiling, and stabilization fixes.

## Why
v0.2.2-rc1 shipped new stdlib modules (fs, str), CLI UX improvements (lint subcommand, -h flag), and QBE cross-compilation fixes. This stable release validates that m4 delivers on its performance promise — at least 10x faster than Python on the hardspeed benchmark — profiles CPU/memory usage, and fixes any remaining rc1 issues.

## Success Criteria
- [ ] m4 is 10x faster than Python on the hardspeed Fibonacci benchmark
- [ ] All existing unit tests pass, no regressions
- [ ] Compute usage (execution time + memory) profiled and documented

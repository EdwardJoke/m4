# v0.4.0 Purpose

## What
Build the m4 toolchain — add `m4 new`/`m4 init` for project scaffolding and `m4 clean cache` for cache management. Restructure the codebase: move all compiler `.zig` files to `src/compiler/`, add `src/toolchain/` for toolchain code. Rename `m4` binary to `m4c` and extract non-compiler functionality into a separate `mein` toolchain manager binary. Update `build.zig` to build both compiler and toolchain simultaneously.

## Why
The `m4` command should be minimal — only contain compiler functionality. Toolchain operations (project init, cache management) should live in a separate binary (`mein`).

## Success Criteria
- [ ] Separate non-compiler functions from `m4` command, move them to `mein` (the separated toolchain manager)
- [ ] Rename `m4` to `m4c`
- [ ] `m4 new project` / `m4 init project` scaffolding working
- [ ] `m4 clean cache` working
- [ ] Codebase restructured: `src/compiler/` + `src/toolchain/`, `build.zig` builds both

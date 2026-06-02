# v0.2.2-rc1 Purpose

## What
Bug fixes, documentation updates, and targeted standard library improvements to stabilize the m4 language before the next development cycle.

## Why
v0.2.1 shipped the `lint` subcommand rename, QBE cross-compilation fixes, and compiler performance optimizations. v0.2.2-rc1 addresses remaining rough edges — documentation staleness, known bugs, and small stdlib gaps — to stabilize the platform.

## Success Criteria
- [ ] CI pipeline verified and Windows deferral documented
- [ ] AGENTS.md status updated to v0.2.2
- [ ] ROADMAP.md removed (info absorbed into AGENTS.md/SPEC.md)
- [ ] Std lib gains at least one new function (e.g. `std.to_string`, string utilities)
- [ ] Tests pass, no regressions

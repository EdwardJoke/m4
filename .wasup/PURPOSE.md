# v0.3.0 Purpose

## What
Ship v0.3.0 with io→std module consolidation, comprehensive API documentation, polished CLI, and optimized error messages.

## Why
The io/std module duplication confuses users and creates maintenance overhead. The language lacks proper API documentation for developer adoption. The CLI and error UX need polish for production readiness.

## Success Criteria
- [ ] No `io` module — all print/read functionality lives in `std` (zero code duplication)
- [ ] SPEC.md and language docs document every public stdlib API
- [ ] CLI help text is clean, error messages are concise with source location info

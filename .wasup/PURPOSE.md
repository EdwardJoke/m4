# v0.2.0 Purpose

## What
Add a QBE compiler backend to m4, compiling to native machine code via QBE IR using both Zig and C++.

## Why
Replace bytecode VM interpretation with native compilation for better performance. The compiler itself is the primary deliverable.

## Success Criteria
1. QBE backend emits valid QBE IR for core language features (functions, control flow, arithmetic)
2. Compiled m4 programs execute correctly via QBE-generated native code
3. All existing examples and tests pass through the QBE backend path

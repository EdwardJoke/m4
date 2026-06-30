#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== m4 (M4 Script) ==="
time "$SCRIPT_DIR/zig-out/bin/m4" "$SCRIPT_DIR/tests/bench/hardspeed_concat.m4"
echo ""
echo "=== Python ==="
time python3 "$SCRIPT_DIR/tests/bench/hardspeed_concat.py"
echo ""
echo "=== Bun/TypeScript ==="
time bun run "$SCRIPT_DIR/tests/bench/hardspeed_concat.ts"

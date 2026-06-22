echo "=== m4 (M4 Script) ==="
time zig-out/bin/m4 tests/bench/hardspeed_concat.m4
echo ""
echo "=== Python ==="
time python3 tests/bench/hardspeed_concat.py
echo ""
echo "=== Bun/TypeScript ==="
time bun run tests/bench/hardspeed_concat.ts

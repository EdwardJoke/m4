echo "=== m4 (M4 Script) ==="
time zig-out/bin/m4 tests/hardspeed_concat.m4
echo ""
echo "=== Python ==="
time python3 tests/hardspeed_concat.py
echo ""
echo "=== Bun/TypeScript ==="
time bun run tests/hardspeed_concat.ts

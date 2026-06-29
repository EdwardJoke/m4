#!/usr/bin/env bash
#
# Memory profiling for m4 benchmarks
# Measures peak RSS using /usr/bin/time -l
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
M4_BIN="$PROJECT_DIR/zig-out/bin/m4"

echo ""
echo "============================================================"
echo "  Memory Profile — Peak RSS (Resident Set Size)"
echo "============================================================"
echo ""

measure() {
    local label="$1"
    shift
    local cmd="$@"
    
    printf "  %-20s" "[$label]"
    local output rss rss_mb wall
    if [[ "$(uname)" == "Darwin" ]]; then
        output=$(/usr/bin/time -l $cmd 2>&1)
        rss=$(echo "$output" | grep "maximum resident" | awk '{print $1}')
        rss_mb=$((rss / 1024 / 1024))
        wall=$(echo "$output" | grep "real" | awk '{print $1}')
    else
        output=$(/usr/bin/time -v $cmd 2>&1)
        rss=$(echo "$output" | grep "Maximum resident" | awk '{print $NF}')
        rss_mb=$((rss / 1024))
        wall=$(echo "$output" | grep "Elapsed" | awk '{print $NF}')
    fi
    printf "Peak RSS: %4d MB | Time: %s\n" "$rss_mb" "$wall"
}

echo "  Benchmark: Recursive Fibonacci (fib 0-30)"
echo "  -----------------------------------------------------------"
measure "m4 (VM)" $M4_BIN $PROJECT_DIR/tests/bench/hardspeed.m4
measure "Python 3" python3 $PROJECT_DIR/tests/bench/hardspeed.py
measure "Bun/TS" bun run $PROJECT_DIR/tests/bench/hardspeed.ts

echo ""
echo "  Benchmark: String Concatenation (5000 iterations)"
echo "  -----------------------------------------------------------"
measure "m4 (VM)" $M4_BIN $PROJECT_DIR/tests/bench/hardspeed_concat.m4
measure "Python 3" python3 $PROJECT_DIR/tests/bench/hardspeed_concat.py
measure "Bun/TS" bun run $PROJECT_DIR/tests/bench/hardspeed_concat.ts

echo ""
echo "  Done."

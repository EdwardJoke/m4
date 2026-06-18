#!/usr/bin/env bash
#
# m4 Benchmark Runner
# Compares m4, Python, and TypeScript (Bun) across multiple benchmark scenarios.
#
# Usage:
#   ./tests/bench.sh                    -- Run all benchmarks (requires hyperfine)
#   ./tests/bench.sh --quick            -- Run all benchmarks with `time` (single runs)
#   ./tests/bench.sh --list             -- List available benchmarks
#   ./tests/bench.sh hardspeed          -- Run specific benchmark only
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
M4_BIN="$PROJECT_DIR/zig-out/bin/m4"

# ── Detect available tools ─────────────────────────────────────────────

HYPERFINE_AVAILABLE=false
if command -v hyperfine &>/dev/null; then
    HYPERFINE_AVAILABLE=true
fi

if [ ! -f "$M4_BIN" ]; then
    echo "Error: m4 binary not found at $M4_BIN"
    echo "Build it first with: zig build -Doptimize=ReleaseFast"
    exit 1
fi

# ── Benchmark definitions ──────────────────────────────────────────────

# Format: name:m4_file:py_file:ts_file:description
BENCHMARKS=(
    "hardspeed:tests/hardspeed.m4:tests/hardspeed.py:tests/hardspeed.ts:Recursive Fibonacci (fib 0-30)"
    "hardspeed_concat:tests/hardspeed_concat.m4:tests/hardspeed_concat.py:tests/hardspeed_concat.ts:String concatenation (500/2000/5000 iterations)"
)

# ── Helpers ────────────────────────────────────────────────────────────

print_header() {
    local text="$1"
    echo ""
    echo "============================================================"
    echo "  $text"
    echo "============================================================"
}

# ── Run with hyperfine ─────────────────────────────────────────────────

run_hyperfine() {
    local name="$1"
    local m4_file="$2"
    local py_file="$3"
    local ts_file="$4"
    local desc="$5"

    print_header "$name - $desc"

    local cmds=()
    local labels=()

    if [ -f "$PROJECT_DIR/$m4_file" ]; then
        cmds+=("$M4_BIN $PROJECT_DIR/$m4_file > /dev/null 2>&1")
        labels+=("m4 (VM)")
    fi

    if command -v python3 &>/dev/null; then
        cmds+=("python3 $PROJECT_DIR/$py_file > /dev/null 2>&1")
        labels+=("Python 3")
    fi

    if command -v bun &>/dev/null; then
        cmds+=("bun run $PROJECT_DIR/$ts_file > /dev/null 2>&1")
        labels+=("Bun/TS")
    fi

    if [ ${#cmds[@]} -lt 2 ]; then
        echo "  Not enough runtimes available."
        return
    fi

    # Run hyperfine with export-json
    local json_out
    json_out=$(mktemp /tmp/m4_bench_XXXXXX.json)
    hyperfine --warmup 3 --min-runs 5 \
        --export-json "$json_out" \
        "${cmds[@]}" 2>&1

    # Parse and display using python3
    if command -v python3 &>/dev/null && [ -f "$json_out" ]; then
        echo ""
        python3 -c "
import json
with open('$json_out') as f:
    data = json.load(f)
results = data.get('results', [])
if results:
    m4_time = None
    for r in results:
        cmd = r.get('command', '')
        if 'm4' in cmd:
            m4_time = r['mean']
    print('  {:<25s} {:>10s} {:>12s}'.format('Runtime', 'Time', 'Ratio'))
    print('  {:<25s} {:>10s} {:>12s}'.format('-------', '----', '-----'))
    for r in results:
        cmd = r.get('command', '')
        mean = r['mean'] * 1000
        stddev = r['stddev'] * 1000
        ratio = '{:.2f}x'.format(mean / (m4_time * 1000)) if m4_time and mean > 0 else '1.00x'
        label = 'm4 (VM)' if 'm4' in cmd else ('Python 3' if 'python3' in cmd else 'Bun/TS')
        print('  {:<25s} {:6.1f}ms +/-{:4.1f}ms {:>10s}'.format(label, mean, stddev, ratio))
" 2>&1 || echo "  (parse complete)"
    fi
    rm -f "$json_out"
}

# ── Run with `time` (fallback) ─────────────────────────────────────────

run_time() {
    local name="$1"
    local m4_file="$2"
    local py_file="$3"
    local ts_file="$4"
    local desc="$5"

    print_header "$name - $desc"

    if [ -f "$PROJECT_DIR/$m4_file" ]; then
        echo "  [m4 (VM)]"
        (cd "$PROJECT_DIR" && time (zig-out/bin/m4 "$m4_file" > /dev/null 2>&1)) 2>&1
        echo ""
    fi

    if command -v python3 &>/dev/null; then
        echo "  [Python 3]"
        (cd "$PROJECT_DIR" && time (python3 "$py_file" > /dev/null 2>&1)) 2>&1
        echo ""
    fi

    if command -v bun &>/dev/null; then
        echo "  [Bun/TypeScript]"
        (cd "$PROJECT_DIR" && time (bun run "$ts_file" > /dev/null 2>&1)) 2>&1
        echo ""
    fi
}

# ── List benchmarks ────────────────────────────────────────────────────

list_benchmarks() {
    echo "Available benchmarks:"
    for entry in "${BENCHMARKS[@]}"; do
        IFS=':' read -r b_name _ _ _ b_desc <<< "$entry"
        printf "  %-20s %s\n" "$b_name" "$b_desc"
    done
}

# ── Main ───────────────────────────────────────────────────────────────

MODE="all"
QUICK=false

if [ $# -eq 0 ]; then
    MODE="all"
elif [ "$1" = "--quick" ]; then
    MODE="all"
    QUICK=true
elif [ "$1" = "--list" ]; then
    list_benchmarks
    exit 0
else
    MODE="$1"
fi

echo ""
GIT_TAG=$(cd "$PROJECT_DIR" && git describe --tags --always 2>/dev/null || echo '?')
echo "  m4 $GIT_TAG Benchmark Suite"
echo "  $(date '+%Y-%m-%d %H:%M')  |  $(uname -msr 2>/dev/null || echo 'unknown')"
if [ "$HYPERFINE_AVAILABLE" = true ] && [ "$QUICK" = false ]; then
    echo "  Mode: hyperfine (5 runs, 3 warmup)"
else
    echo "  Mode: time (single run)"
fi

for entry in "${BENCHMARKS[@]}"; do
    IFS=':' read -r b_name b_m4 b_py b_ts b_desc <<< "$entry"

    if [ "$MODE" != "all" ] && [ "$MODE" != "$b_name" ]; then
        continue
    fi

    if [ "$HYPERFINE_AVAILABLE" = true ] && [ "$QUICK" = false ]; then
        run_hyperfine "$b_name" "$b_m4" "$b_py" "$b_ts" "$b_desc"
    else
        run_time "$b_name" "$b_m4" "$b_py" "$b_ts" "$b_desc"
    fi
done

echo ""
echo "  Done."

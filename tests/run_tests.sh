#!/usr/bin/env bash
#
# m4 Test Runner
# Runs all .m4 test files in tests/ and reports pass/fail.
#
# Usage:
#   ./tests/run_tests.sh               # Run all tests
#   ./tests/run_tests.sh --verbose     # Show full output
#   ./tests/run_tests.sh --list        # List test categories
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
M4_BIN="$PROJECT_DIR/zig-out/bin/m4"
UNIT_DIR="$SCRIPT_DIR/unit"
BENCH_DIR="$SCRIPT_DIR/bench"

PASS=0
FAIL=0
SKIP=0
VERBOSE=false

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ── Helpers ────────────────────────────────────────────────────────────

print_header() {
    echo ""
    echo "============================================================"
    echo "  $1"
    echo "============================================================"
}

pass() {
    local name="$1"
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}✓${NC}  $name"
}

fail() {
    local name="$1"
    local reason="$2"
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}✗${NC}  $name — $reason"
}

skip() {
    local name="$1"
    local reason="$2"
    SKIP=$((SKIP + 1))
    echo -e "  ${YELLOW}−${NC}  $name ($reason)"
}

# ── Sanity checks ──────────────────────────────────────────────────────

if [ ! -f "$M4_BIN" ]; then
    echo "Error: m4 binary not found at $M4_BIN"
    echo "Build it first with: zig build"
    exit 1
fi

if [ $# -gt 0 ] && [ "$1" = "--verbose" ]; then
    VERBOSE=true
elif [ $# -gt 0 ] && [ "$1" = "--list" ]; then
    echo ""
    echo "Test files in tests/unit/:"
    echo ""
    for f in "$UNIT_DIR"/*.m4; do
        base=$(basename "$f" .m4)
        echo "  $base.m4"
    done
    echo ""
    echo "Benchmark files in tests/bench/:"
    echo ""
    for f in "$BENCH_DIR"/*.m4; do
        base=$(basename "$f" .m4)
        echo "  $base.m4"
    done
    exit 0
fi

# ── Test definitions ───────────────────────────────────────────────────
#
# Each test entry:  file:sentinel:description
#   file       — the .m4 file name (without extension)
#   sentinel   — expected string in stdout (empty = skip check)
#   description— human-readable description
#
# Files without a sentinel check pass if exit code is 0.

declare -a TESTS=(
    "test_types:--- All type tests passed ---:Primitive types (i8/i16/i32/i64/u8/u32/f32/f64/bool/str)"
    "test_arith:--- All arithmetic tests passed ---:Arithmetic operations, comparisons, precedence"
    "test_control_flow:--- All control flow tests passed ---:if/elif/else, loop, for, continue, esc"
    "test_vec:--- All vector tests passed ---:Vector creation, indexing, iteration"
    "test_struct:--- All struct tests passed ---:Struct types, literals, field access"
    "test_functions:--- All function tests passed ---:Functions, parameters, return values, recursion"
    "test_errors:--- All error handling tests passed ---:Error patterns, nil, safe indexing"
    "test_str_module:--- All str module tests passed ---:str.len, str.slice"
    "test_fs_module:--- All fs module tests passed ---:fs.read, fs.write, fs.exists, fs.delete"
    "string_test::String operations with std.readln (stdin piped)"
    "string_ops:done:String comparison operations"
)

# ── Benchmark files (test runner summary) ──────────────────────────────

BENCHMARK_FILES=("hardspeed" "hardspeed_concat")

# ── Main test loop ─────────────────────────────────────────────────────

print_header "m4 Test Suite"

echo ""
echo "  Binary: $M4_BIN"
echo "  CWD:    $PROJECT_DIR"
echo ""

for entry in "${TESTS[@]}"; do
    IFS=':' read -r filename sentinel description <<< "$entry"

    test_file="$UNIT_DIR/$filename.m4"
    if [ ! -f "$test_file" ]; then
        fail "$filename.m4" "File not found"
        continue
    fi

    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "  ── $filename: $description ──"
    fi

    # Run the test, capturing stdout and stderr
    # Special case: string_test.m4 has std.readln() — pipe input to it
    if [ "$filename" = "string_test" ]; then
        output=$(echo "test_input" | "$M4_BIN" "$test_file" 2>&1) || true
    else
        output=$("$M4_BIN" "$test_file" 2>&1) || true
    fi
    exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        fail "$filename.m4" "Exit code $exit_code"
        if [ "$VERBOSE" = true ]; then
            echo ""
            echo "  Output:"
            echo "$output" | sed 's/^/    /'
            echo ""
        fi
        continue
    fi

    # Check sentinel string (if specified and non-empty)
    if [ -n "$sentinel" ]; then            if ! echo "$output" | grep -qF -- "$sentinel"; then
            fail "$filename.m4" "Missing sentinel: \"$sentinel\""
            if [ "$VERBOSE" = true ]; then
                echo ""
                echo "  Output:"
                echo "$output" | sed 's/^/    /'
                echo ""
            fi
            continue
        fi
    fi

    # With sentinel found (or no sentinel to check), test passes
    pass "$filename.m4"
done

# ── Summary ────────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL))
echo ""
echo "────────────────────────────────────────────────────────────"
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC} (of $((TOTAL + SKIP)) total)"
echo "────────────────────────────────────────────────────────────"

# Note benchmark files
if [ "$VERBOSE" = true ]; then
    echo ""
    echo "  Benchmark files (not run as tests):"
    for bf in "${BENCHMARK_FILES[@]}"; do
        echo "    $bf.m4"
    done
fi

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

# Test: Arithmetic Operations
# Tests all arithmetic, comparison, logical, and unary operators
# Tests operator precedence and edge cases

use std

fun test_basic_arithmetic() i32
    mut fail i32 = 0
    std.println("--- Basic Arithmetic ---")

    let a i32 = 10
    let b i32 = 3

    std.print("10 + 3 = ")
    std.println(a + b)
    if a + b != 13
        fail = fail + 1

    std.print("10 - 3 = ")
    std.println(a - b)
    if a - b != 7
        fail = fail + 1

    std.print("10 * 3 = ")
    std.println(a * b)
    if a * b != 30
        fail = fail + 1

    std.print("10 / 3 = ")
    std.println(a / b)
    if a / b != 3
        fail = fail + 1

    std.print("10 % 3 = ")
    std.println(a % b)
    if a % b != 1
        fail = fail + 1

    ret fail

fun test_arithmetic_edge_cases() i32
    mut fail i32 = 0
    std.println("--- Edge Cases ---")

    # Large numbers
    let big i64 = 10000000000
    let big2 i64 = 20000000000
    std.print("big + big2 = ")
    std.println(big + big2)
    if big + big2 != 30000000000
        fail = fail + 1

    # Negative numbers
    let neg i32 = -5
    let pos i32 = 10
    std.print("-5 + 10 = ")
    std.println(neg + pos)
    if neg + pos != 5
        fail = fail + 1

    std.print("10 - (-5) = ")
    std.println(pos - neg)
    if pos - neg != 15
        fail = fail + 1

    # Zero operations
    let zero i32 = 0
    std.print("10 + 0 = ")
    std.println(pos + zero)
    if pos + zero != 10
        fail = fail + 1

    std.print("10 - 0 = ")
    std.println(pos - zero)
    if pos - zero != 10
        fail = fail + 1

    std.print("10 * 0 = ")
    std.println(pos * zero)
    if pos * zero != 0
        fail = fail + 1

    ret fail

fun test_unary_negation() i32
    mut fail i32 = 0
    std.println("--- Unary Negation ---")

    let x i32 = 42
    let neg_x = -x
    std.print("-42 = ")
    std.println(neg_x)
    if neg_x != -42
        fail = fail + 1

    let y i32 = -10
    let neg_y = -y
    std.print("-(-10) = ")
    std.println(neg_y)
    if neg_y != 10
        fail = fail + 1

    ret fail

fun test_comparisons() i32
    mut fail i32 = 0
    std.println("--- Comparisons ---")

    let a i32 = 42
    let b i32 = 100

    std.print("42 == 100: ")
    std.println(a == b)
    if a == b
        fail = fail + 1

    std.print("42 != 100: ")
    std.println(a != b)
    if a != b == false
        fail = fail + 1

    std.print("42 < 100: ")
    std.println(a < b)
    if a < b == false
        fail = fail + 1

    std.print("42 > 100: ")
    std.println(a > b)
    if a > b
        fail = fail + 1

    std.print("42 <= 100: ")
    std.println(a <= b)
    if a <= b == false
        fail = fail + 1

    std.print("42 >= 100: ")
    std.println(a >= b)
    if a >= b
        fail = fail + 1

    std.print("42 <= 42: ")
    std.println(a <= a)
    if a <= a == false
        fail = fail + 1

    std.print("42 >= 42: ")
    std.println(a >= a)
    if a >= a == false
        fail = fail + 1

    ret fail

fun test_logical_ops() i32
    mut fail i32 = 0
    std.println("--- Logical Operators ---")

    let t = true
    let f = false

    std.print("true && true = ")
    std.println(t && t)
    if !(t && t)
        fail = fail + 1

    std.print("true && false = ")
    std.println(t && f)
    if t && f
        fail = fail + 1

    std.print("false && true = ")
    std.println(f && t)
    if f && t
        fail = fail + 1

    std.print("false && false = ")
    std.println(f && f)
    if f && f
        fail = fail + 1

    std.print("true || false = ")
    std.println(t || f)
    if !(t || f)
        fail = fail + 1

    std.print("false || false = ")
    std.println(f || f)
    if f || f
        fail = fail + 1

    std.print("!true = ")
    std.println(!t)
    if !t
        fail = fail + 1

    std.print("!false = ")
    std.println(!f)
    if !f == false
        fail = fail + 1

    ret fail

fun test_operator_precedence() i32
    mut fail i32 = 0
    std.println("--- Operator Precedence ---")

    # * and / before + and -
    let r1 = 2 + 3 * 4
    std.print("2 + 3 * 4 = ")
    std.println(r1)
    if r1 != 14
        fail = fail + 1

    let r2 = 10 - 6 / 3
    std.print("10 - 6 / 3 = ")
    std.println(r2)
    if r2 != 8
        fail = fail + 1

    let r3 = 10 / 2 + 3
    std.print("10 / 2 + 3 = ")
    std.println(r3)
    if r3 != 8
        fail = fail + 1

    # Comparison with arithmetic
    let r4 = 10 + 5 > 12
    std.print("10 + 5 > 12 = ")
    std.println(r4)
    if r4 == false
        fail = fail + 1

    let r5 = 10 + 5 < 12
    std.print("10 + 5 < 12 = ")
    std.println(r5)
    if r5
        fail = fail + 1

    # Modulo
    let r6 = 17 % 5
    std.print("17 % 5 = ")
    std.println(r6)
    if r6 != 2
        fail = fail + 1

    ret fail

pub fun main() i32
    let failures = 0

    failures = failures + test_basic_arithmetic()
    failures = failures + test_arithmetic_edge_cases()
    failures = failures + test_unary_negation()
    failures = failures + test_comparisons()
    failures = failures + test_logical_ops()
    failures = failures + test_operator_precedence()

    if failures == 0
        std.println("--- All arithmetic tests passed ---")
    else
        std.print("--- FAILED: ")
        std.print(failures)
        std.println(" test(s) failed ---")

    ret failures

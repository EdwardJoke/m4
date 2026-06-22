# Test: Arithmetic Operations
# Tests all arithmetic, comparison, logical, and unary operators
# Tests operator precedence and edge cases

use std

fun test_basic_arithmetic()
    std.println("--- Basic Arithmetic ---")

    let a i32 = 10
    let b i32 = 3

    std.print("10 + 3 = ")
    std.println(a + b)

    std.print("10 - 3 = ")
    std.println(a - b)

    std.print("10 * 3 = ")
    std.println(a * b)

    std.print("10 / 3 = ")
    std.println(a / b)

    std.print("10 % 3 = ")
    std.println(a % b)

fun test_arithmetic_edge_cases()
    std.println("--- Edge Cases ---")

    # Large numbers
    let big i64 = 10000000000
    let big2 i64 = 20000000000
    std.print("big + big2 = ")
    std.println(big + big2)

    # Negative numbers
    let neg i32 = -5
    let pos i32 = 10
    std.print("-5 + 10 = ")
    std.println(neg + pos)

    std.print("10 - (-5) = ")
    std.println(pos - neg)

    # Zero operations
    let zero i32 = 0
    std.print("10 + 0 = ")
    std.println(pos + zero)

    std.print("10 - 0 = ")
    std.println(pos - zero)

    std.print("10 * 0 = ")
    std.println(pos * zero)

fun test_unary_negation()
    std.println("--- Unary Negation ---")

    let x i32 = 42
    let neg_x = -x
    std.print("-42 = ")
    std.println(neg_x)

    let y i32 = -10
    let neg_y = -y
    std.print("-(-10) = ")
    std.println(neg_y)

fun test_comparisons()
    std.println("--- Comparisons ---")

    let a i32 = 42
    let b i32 = 100

    std.print("42 == 100: ")
    std.println(a == b)

    std.print("42 != 100: ")
    std.println(a != b)

    std.print("42 < 100: ")
    std.println(a < b)

    std.print("42 > 100: ")
    std.println(a > b)

    std.print("42 <= 100: ")
    std.println(a <= b)

    std.print("42 >= 100: ")
    std.println(a >= b)

    std.print("42 <= 42: ")
    std.println(a <= a)

    std.print("42 >= 42: ")
    std.println(a >= a)

fun test_logical_ops()
    std.println("--- Logical Operators ---")

    let t = true
    let f = false

    std.print("true && true = ")
    std.println(t && t)

    std.print("true && false = ")
    std.println(t && f)

    std.print("false && true = ")
    std.println(f && t)

    std.print("false && false = ")
    std.println(f && f)

    std.print("true || false = ")
    std.println(t || f)

    std.print("false || false = ")
    std.println(f || f)

    std.print("!true = ")
    std.println(!t)

    std.print("!false = ")
    std.println(!f)

fun test_operator_precedence()
    std.println("--- Operator Precedence ---")

    # * and / before + and -
    let r1 = 2 + 3 * 4
    std.print("2 + 3 * 4 = ")
    std.println(r1)

    let r2 = 10 - 6 / 3
    std.print("10 - 6 / 3 = ")
    std.println(r2)

    let r3 = 10 / 2 + 3
    std.print("10 / 2 + 3 = ")
    std.println(r3)

    # Comparison with arithmetic
    let r4 = 10 + 5 > 12
    std.print("10 + 5 > 12 = ")
    std.println(r4)

    let r5 = 10 + 5 < 12
    std.print("10 + 5 < 12 = ")
    std.println(r5)

    # Modulo
    let r6 = 17 % 5
    std.print("17 % 5 = ")
    std.println(r6)

pub fun main() i32
    test_basic_arithmetic()
    test_arithmetic_edge_cases()
    test_unary_negation()
    test_comparisons()
    test_logical_ops()
    test_operator_precedence()

    std.println("--- All arithmetic tests passed ---")
    ret 0

# Test: Control Flow
# Tests: if/elif/else, loop, for, continue, esc, nested control flow

use std

fun test_if_elif_else() i32
    mut fail i32 = 0
    std.println("--- if/elif/else ---")

    # Simple if
    if true
        std.println("simple if: true branch taken")

    # if-else
    if false
        std.println("should NOT see this")
    else
        std.println("if-else: false branch taken")

    # if-elif-else chain
    let x i32 = 50

    if x < 20
        std.println("x < 20")
    elif x < 40
        std.println("x < 40")
    elif x < 60
        std.println("x < 60 (this should print)")
    elif x < 80
        std.println("x < 80")
    else
        std.println("x >= 80")

    if x != 50
        fail = fail + 1

    # if with no else
    let y i32 = 100
    if y > 50
        std.println("y > 50: no else branch")

    if y != 100
        fail = fail + 1

    # Edge: conditionals with comparisons
    if x == 50
        std.println("x == 50: equality works")

    ret fail

fun test_loop() i32
    mut fail i32 = 0
    std.println("--- loop ---")

    mut count i32 = 0
    loop
        std.println(count)
        count = count + 1
        if count >= 3
            esc

    if count != 3
        std.print("FAIL: expected count=3, got ")
        std.println(count)
        fail = fail + 1

    ret fail

fun test_loop_with_continue() i32
    std.println("--- loop with continue ---")

    mut n i32 = 0
    loop
        n = n + 1
        if n > 6
            esc
        if n % 2 == 0
            continue
        std.println(n)

    ret 0

fun test_for_over_vec() i32
    std.println("--- for over vector ---")

    for fruit in ["apple", "banana", "cherry"]
        std.println(fruit)

    # for over i32 vec
    for num in [10, 20, 30, 40]
        std.println(num)

    ret 0

fun test_for_over_range() i32
    std.println("--- for over range ---")

    for n in std.range(0, 5)
        std.println(n)

    # range with non-zero start
    for n in std.range(3, 7)
        std.println(n)

    ret 0

fun test_nested_if() i32
    mut fail i32 = 0
    std.println("--- Nested if ---")

    let a i32 = 10
    let b i32 = 20

    if a > 5
        if b > 15
            std.println("nested if: both conditions true")
        else
            std.println("nested if: outer true, inner false")

    if a < 5
        if b > 15
            std.println("nested if: should not see")
    else
        std.println("nested if: outer else")

    if a != 10
        fail = fail + 1

    if b != 20
        fail = fail + 1

    ret fail

fun test_nested_loops() i32
    std.println("--- Nested loops ---")

    for x in [1, 2, 3]
        for y in [4, 5, 6]
            std.println(x * y)

    ret 0

fun test_for_with_esc() i32
    std.println("--- for with esc ---")

    for n in std.range(0, 10)
        if n == 4
            esc
        std.println(n)

    ret 0

pub fun main() i32
    mut failures i32 = 0

    failures = failures + test_if_elif_else()
    failures = failures + test_loop()
    failures = failures + test_loop_with_continue()
    failures = failures + test_for_over_vec()
    failures = failures + test_for_over_range()
    failures = failures + test_nested_if()
    failures = failures + test_nested_loops()
    failures = failures + test_for_with_esc()

    if failures == 0
        std.println("--- All control flow tests passed ---")
    else
        std.print("--- FAILED: ")
        std.print(failures)
        std.println(" test(s) failed ---")

    ret failures

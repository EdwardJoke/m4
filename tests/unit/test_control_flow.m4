# Test: Control Flow
# Tests: if/elif/else, loop, for, continue, esc, nested control flow

use std

fun test_if_elif_else()
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

    # if with no else
    let y i32 = 100
    if y > 50
        std.println("y > 50: no else branch")

    # Edge: conditionals with comparisons
    if x == 50
        std.println("x == 50: equality works")

fun test_loop()
    std.println("--- loop ---")

    mut count i32 = 0
    loop
        std.println(count)
        count = count + 1
        if count >= 3
            esc

fun test_loop_with_continue()
    std.println("--- loop with continue ---")

    mut n i32 = 0
    loop
        n = n + 1
        if n > 6
            esc
        if n % 2 == 0
            continue
        std.println(n)

fun test_for_over_vec()
    std.println("--- for over vector ---")

    for fruit in ["apple", "banana", "cherry"]
        std.println(fruit)

    # for over i32 vec
    for num in [10, 20, 30, 40]
        std.println(num)

fun test_for_over_range()
    std.println("--- for over range ---")

    for n in std.range(0, 5)
        std.println(n)

    # range with non-zero start
    for n in std.range(3, 7)
        std.println(n)

fun test_nested_if()
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

fun test_nested_loops()
    std.println("--- Nested loops ---")

    for x in [1, 2, 3]
        for y in [4, 5, 6]
            std.println(x * y)

fun test_for_with_esc()
    std.println("--- for with esc ---")

    for n in std.range(0, 10)
        if n == 4
            esc
        std.println(n)

pub fun main() i32
    test_if_elif_else()
    test_loop()
    test_loop_with_continue()
    test_for_over_vec()
    test_for_over_range()
    test_nested_if()
    test_nested_loops()
    test_for_with_esc()

    std.println("--- All control flow tests passed ---")
    ret 0

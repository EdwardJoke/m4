# Nested Patterns Demo
# Demonstrates: nested if-else, nested loops, complex combinations

use std

fun print_triangle(size i32)
    mut row i32 = 1
    loop
        if row > size
            esc

        mut col i32 = 0
        loop
            if col >= row
                esc
            std.print("*")
            col = col + 1

        std.println("")
        row = row + 1

fun classify_number(n i32)
    std.print(n)
    std.print(" is ")

    if n > 0
        if n % 2 == 0
            if n % 10 == 0
                std.println("positive, even, and a multiple of 10")
            else
                std.println("positive and even")
        else
            std.println("positive and odd")
    elif n < 0
        std.println("negative")
    else
        std.println("zero")

fun multiplication_table(size i32)
    std.println("Multiplication Table:")
    for a in std.range(1, size + 1)
        for b in std.range(1, size + 1)
            std.print(a * b)
            std.print(" ")
        std.println("")

fun find_in_vec(items, target i32) bool
    for item in items
        if item == target
            ret true
    ret false

pub fun main() i32
    std.println("=== Triangle Pattern ===")
    print_triangle(5)

    std.println("=== Number Classification ===")
    classify_number(10)
    classify_number(7)
    classify_number(-3)
    classify_number(0)
    classify_number(20)

    std.println("=== Multiplication Table ===")
    multiplication_table(5)

    std.println("=== Find in Vector ===")
    let numbers = [10, 20, 30, 40, 50]

    if find_in_vec(numbers, 30)
        std.println("Found 30 in numbers")
    else
        std.println("Did NOT find 30 in numbers")

    if find_in_vec(numbers, 99)
        std.println("Found 99 in numbers (should NOT happen)")
    else
        std.println("99 not found in numbers (expected)")

    std.println("=== Nested Patterns Demo Complete ===")

    ret 0

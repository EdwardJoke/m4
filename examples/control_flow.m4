# Control Flow
# Demonstrates: if/elif/else, loop, for, continue, esc

use std

fun classify_temp(t i32)
    if t > 40
        std.println("Extremely hot")
    elif t > 30
        std.println("Hot")
    elif t > 20
        std.println("Warm")
    elif t > 10
        std.println("Cool")
    else
        std.println("Cold")

fun countdown(start i32)
    mut n i32 = start
    loop
        std.println(n)
        n = n - 1

        if n < 0
            esc

fun print_evens(limit i32)
    mut n i32 = 0
    loop
        n = n + 1
        if n > limit
            esc

        if n % 2 != 0
            continue

        std.println(n)

pub fun main() i32
    std.println("--- Temperature Classification ---")
    classify_temp(45)
    classify_temp(35)
    classify_temp(25)
    classify_temp(15)
    classify_temp(5)

    std.println("--- Countdown ---")
    countdown(5)

    std.println("--- Even Numbers ---")
    print_evens(10)

    std.println("--- For Loop ---")
    for fruit in ["apple", "banana", "cherry"]
        std.println(fruit)

    ret 0

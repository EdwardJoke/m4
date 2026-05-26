# Control Flow
# Demonstrates: if/elif/else, loop, for, continue, esc

use io

fun classify_temp(t i32)
    if t > 40
        io.println("Extremely hot")
    elif t > 30
        io.println("Hot")
    elif t > 20
        io.println("Warm")
    elif t > 10
        io.println("Cool")
    else
        io.println("Cold")

fun countdown(start i32)
    mut n i32 = start
    loop
        io.println(n)
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

        io.println(n)

pub fun main() i32
    io.println("--- Temperature Classification ---")
    classify_temp(45)
    classify_temp(35)
    classify_temp(25)
    classify_temp(15)
    classify_temp(5)

    io.println("--- Countdown ---")
    countdown(5)

    io.println("--- Even Numbers ---")
    print_evens(10)

    io.println("--- For Loop ---")
    for fruit in ["apple", "banana", "cherry"]
        io.println(fruit)

    ret 0

# FizzBuzz
# Demonstrates: loop, if/elif/else, modulo operator, mutable variables

use std

pub fun main() i32
    mut n i32 = 1

    loop
        if n % 15 == 0
            std.println("FizzBuzz")
        elif n % 3 == 0
            std.println("Fizz")
        elif n % 5 == 0
            std.println("Buzz")
        else
            std.println(n)

        n = n + 1

        if n > 100
            esc

    ret 0

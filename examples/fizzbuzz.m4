# FizzBuzz
# Demonstrates: loop, if/elif/else, modulo operator, mutable variables

use io

pub fun main() i32
    mut n i32 = 1

    loop
        if n % 15 == 0
            io.println("FizzBuzz")
        elif n % 3 == 0
            io.println("Fizz")
        elif n % 5 == 0
            io.println("Buzz")
        else
            io.println(n)

        n = n + 1

        if n > 100
            esc

    ret 0

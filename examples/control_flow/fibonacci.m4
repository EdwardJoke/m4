# Fibonacci
# Demonstrates: function declarations, recursion, for loops, vectors

use std

fun fib(n i32) i32
    if n <= 1
        ret n
    else
        ret fib(n - 1) + fib(n - 2)

pub fun main() i32
    std.println("First 20 Fibonacci numbers:")

    for n in std.range(0, 20)
        let result i32 = fib(n)
        std.println(result)

    ret 0

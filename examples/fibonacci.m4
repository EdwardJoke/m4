# Fibonacci
# Demonstrates: function declarations, recursion, for loops, vectors

use io

fun fib(n i32) i32
    if n <= 1
        ret n
    else
        ret fib(n - 1) + fib(n - 2)

pub fun main() i32
    io.println("First 20 Fibonacci numbers:")

    for n in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]
        let result i32 = fib(n)
        io.println(result)

    ret 0

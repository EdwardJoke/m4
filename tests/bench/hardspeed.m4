use std

fun fib(n i32) i32
    if n <= 1
        ret n
    else
        ret fib(n - 1) + fib(n - 2)

pub fun main()
    for n in std.range(0, 30)
        let result i32 = fib(n)
        std.println(result)
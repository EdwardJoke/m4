# Test: Functions
# Tests: function declarations, parameters, return values, recursion, nested calls

use std

fun test_no_params()
    std.println("--- no params ---")

fun add(a i32, b i32) i32
    ret a + b

fun sub(a i32, b i32) i32
    ret a - b

fun mul(a i32, b i32) i32
    ret a * b

fun div(a i32, b i32) i32
    ret a / b

fun factorial(n i32) i32
    if n <= 1
        ret 1
    else
        ret n * factorial(n - 1)

fun fib(n i32) i32
    if n <= 1
        ret n
    else
        ret fib(n - 1) + fib(n - 2)

fun is_even(n i32) bool
    ret n % 2 == 0

fun max_of_two(a i32, b i32) i32
    if a > b
        ret a
    else
        ret b

fun test_basic_functions()
    std.println("--- Basic Functions ---")

    test_no_params()

    let result = add(5, 3)
    std.print("add(5, 3) = ")
    std.println(result)

    std.print("sub(10, 4) = ")
    std.println(sub(10, 4))

    std.print("mul(6, 7) = ")
    std.println(mul(6, 7))

    std.print("div(20, 4) = ")
    std.println(div(20, 4))

fun test_boolean_return()
    std.println("--- Boolean Returns ---")

    std.print("is_even(10) = ")
    std.println(is_even(10))

    std.print("is_even(7) = ")
    std.println(is_even(7))

    if is_even(10)
        std.println("10 is even")

    if is_even(7)
        std.println("7 is even (should not print)")
    else
        std.println("7 is odd")

fun test_complex_return()
    std.println("--- Complex Return ---")

    let m = max_of_two(100, 50)
    std.print("max_of_two(100, 50) = ")
    std.println(m)

    let m2 = max_of_two(30, 80)
    std.print("max_of_two(30, 80) = ")
    std.println(m2)

fun test_recursive_factorial()
    std.println("--- Recursive Factorial ---")

    std.print("factorial(0) = ")
    std.println(factorial(0))

    std.print("factorial(1) = ")
    std.println(factorial(1))

    std.print("factorial(5) = ")
    std.println(factorial(5))

    std.print("factorial(10) = ")
    std.println(factorial(10))

fun test_recursive_fib()
    std.println("--- Recursive Fibonacci ---")

    std.print("fib(0) = ")
    std.println(fib(0))

    std.print("fib(1) = ")
    std.println(fib(1))

    std.print("fib(5) = ")
    std.println(fib(5))

    std.print("fib(10) = ")
    std.println(fib(10))

pub fun main() i32
    test_basic_functions()
    test_boolean_return()
    test_complex_return()
    test_recursive_factorial()
    test_recursive_fib()

    std.println("--- All function tests passed ---")
    ret 0

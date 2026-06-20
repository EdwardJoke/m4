# Math and Operators
# Demonstrates: arithmetic, comparison, logical operators, operator precedence

use std

pub fun main() i32
    std.println("--- Arithmetic ---")

    let a i32 = 10
    let b i32 = 3

    std.print("a + b = ")
    std.println(a + b)

    std.print("a - b = ")
    std.println(a - b)

    std.print("a * b = ")
    std.println(a * b)

    std.print("a / b = ")
    std.println(a / b)

    std.print("a % b = ")
    std.println(a % b)

    std.println("--- Float Arithmetic ---")

    let pi f64 = 3.14159
    let e f64 = 2.71828

    std.print("pi + e = ")
    std.println(pi + e)

    std.print("pi * e = ")
    std.println(pi * e)

    std.println("--- Comparisons ---")

    let x i32 = 42
    let y i32 = 100

    std.print("x == y: ")
    std.println(x == y)

    std.print("x != y: ")
    std.println(x != y)

    std.print("x > y: ")
    std.println(x > y)

    std.print("x < y: ")
    std.println(x < y)

    std.print("x >= y: ")
    std.println(x >= y)

    std.print("x <= y: ")
    std.println(x <= y)

    std.println("--- Logical Operators ---")

    let t = true
    let f = false

    std.print("t && t: ")
    std.println(t && t)

    std.print("t && f: ")
    std.println(t && f)

    std.print("t || f: ")
    std.println(t || f)

    std.print("f || f: ")
    std.println(f || f)

    std.print("!t: ")
    std.println(!t)

    std.print("!f: ")
    std.println(!f)

    std.println("--- Unary Negation ---")

    let positive i32 = 5
    let negative = -positive

    std.print("positive: ")
    std.println(positive)

    std.print("negative: ")
    std.println(negative)

    std.println("--- String Concatenation ---")

    let first str = "Hello"
    let last str = "World"
    std.println(first + ", " + last + "!")

    ret 0

# Math and Operators
# Demonstrates: arithmetic, comparison, logical operators, operator precedence

use io

pub fun main() i32
    io.println("--- Arithmetic ---")

    let a i32 = 10
    let b i32 = 3

    io.print("a + b = ")
    io.println(a + b)

    io.print("a - b = ")
    io.println(a - b)

    io.print("a * b = ")
    io.println(a * b)

    io.print("a / b = ")
    io.println(a / b)

    io.print("a % b = ")
    io.println(a % b)

    io.println("--- Float Arithmetic ---")

    let pi f64 = 3.14159
    let e f64 = 2.71828

    io.print("pi + e = ")
    io.println(pi + e)

    io.print("pi * e = ")
    io.println(pi * e)

    io.println("--- Comparisons ---")

    let x i32 = 42
    let y i32 = 100

    io.print("x == y: ")
    io.println(x == y)

    io.print("x != y: ")
    io.println(x != y)

    io.print("x > y: ")
    io.println(x > y)

    io.print("x < y: ")
    io.println(x < y)

    io.print("x >= y: ")
    io.println(x >= y)

    io.print("x <= y: ")
    io.println(x <= y)

    io.println("--- Logical Operators ---")

    let t = true
    let f = false

    io.print("t && t: ")
    io.println(t && t)

    io.print("t && f: ")
    io.println(t && f)

    io.print("t || f: ")
    io.println(t || f)

    io.print("f || f: ")
    io.println(f || f)

    io.print("!t: ")
    io.println(!t)

    io.print("!f: ")
    io.println(!f)

    io.println("--- Unary Negation ---")

    let positive i32 = 5
    let negative = -positive

    io.print("positive: ")
    io.println(positive)

    io.print("negative: ")
    io.println(negative)

    io.println("--- String Concatenation ---")

    let first str = "Hello"
    let last str = "World"
    io.println(first + ", " + last + "!")

    ret 0

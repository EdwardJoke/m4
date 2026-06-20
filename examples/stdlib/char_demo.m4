# Char Type Demo
# Demonstrates: string indexing returns chars

use std
use str

fun analyze_string(s str)
    std.print("String: ")
    std.println(s)

    std.print("First char: ")
    std.println(s[0])

    std.print("Second char: ")
    std.println(s[1])

    let last_idx = str.len(s) - 1
    std.print("Last char: ")
    std.println(s[last_idx])

pub fun main() i32
    std.println("--- String Indexing Demo ---")

    analyze_string("Hello")

    # Indexing into strings
    let greeting str = "World"
    std.print("greeting[0] = ")
    std.println(greeting[0])

    std.print("greeting[4] = ")
    std.println(greeting[4])

    ret 0

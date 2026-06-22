# Strings Demo
# Demonstrates: string concatenation, comparison, indexing, slicing, length

use std
use str

fun print_line(label str, value)
    std.print(label)
    std.println(value)

fun reverse_string(s str) str
    mut result str = ""
    let len = str.len(s)
    mut i i32 = len - 1

    loop
        if i < 0
            esc
        let ch = s[i]
        std.print(ch)
        i = i - 1

    std.println("")
    ret result

pub fun main() i32
    std.println("=== String Operations Demo ===")

    let greeting str = "Hello"
    let name str = "m4"

    # Concatenation
    let message str = greeting + ", " + name + "!"
    print_line("Concat: ", message)

    # String length
    let len = str.len(message)
    print_line("Length: ", len)

    # Substring
    let part = str.slice(message, 0, 5)
    print_line("First 5 chars: ", part)

    # String indexing
    let c1 = message[0]
    std.print("Char at 0: ")
    std.println(c1)

    let c2 = message[7]
    std.print("Char at 7: ")
    std.println(c2)

    # Comparison
    let a str = "apple"
    let b str = "banana"

    if a < b
        std.println("apple < banana is true")

    if b > a
        std.println("banana > apple is true")

    if a == "apple"
        std.println("a == apple is true")

    # Empty string
    let empty str = ""
    let empty_len = str.len(empty)
    print_line("Empty string length: ", empty_len)

    std.println("=== Strings Demo Complete ===")

    ret 0

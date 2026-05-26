# Vectors and Iteration
# Demonstrates: vector literals, indexing, for loops

use std

fun sum(vec) i32
    mut total i32 = 0

    for v in vec
        total = total + v

    ret total

fun max(vec)
    mut best = vec[0]

    for v in vec
        if v > best
            best = v

    ret best

fun print_indexed(items)
    mut idx i32 = 0
    for item in items
        std.print("[")
        std.print(idx)
        std.print("] ")
        std.println(item)
        idx = idx + 1

pub fun main() i32
    let numbers = [10, 20, 30, 40, 50]
    let names = ["Alice", "Bob", "Charlie", "Diana"]

    std.println("Numbers:")
    for n in numbers
        std.println(n)

    let s = sum(numbers)
    std.print("Sum: ")
    std.println(s)

    let m = max(numbers)
    std.print("Max: ")
    std.println(m)

    std.println("Indexed Names:")
    print_indexed(names)

    std.print("First number: ")
    std.println(numbers[0])

    std.print("Last number: ")
    std.println(numbers[4])

    std.println("Nested iteration:")
    for x in [1, 2, 3]
        for y in [4, 5, 6]
            std.println(x * y)

    ret 0

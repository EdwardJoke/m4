# Vectors and Iteration
# Demonstrates: vector literals, indexing, for loops

use io

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
        io.print("[")
        io.print(idx)
        io.print("] ")
        io.println(item)
        idx = idx + 1

pub fun main() i32
    let numbers = [10, 20, 30, 40, 50]
    let names = ["Alice", "Bob", "Charlie", "Diana"]

    io.println("Numbers:")
    for n in numbers
        io.println(n)

    let s = sum(numbers)
    io.print("Sum: ")
    io.println(s)

    let m = max(numbers)
    io.print("Max: ")
    io.println(m)

    io.println("Indexed Names:")
    print_indexed(names)

    io.print("First number: ")
    io.println(numbers[0])

    io.print("Last number: ")
    io.println(numbers[4])

    io.println("Nested iteration:")
    for x in [1, 2, 3]
        for y in [4, 5, 6]
            io.println(x * y)

    ret 0

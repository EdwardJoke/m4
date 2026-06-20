# Test: Vectors
# Tests: vector literals, indexing, for loops, nested vectors, functions with vectors

use std

fun test_vec_creation()
    std.println("--- Vector Creation ---")

    let numbers = [10, 20, 30, 40, 50]
    let names = ["Alice", "Bob", "Charlie"]

    std.println("numbers vec:")
    for n in numbers
        std.println(n)

    std.println("names vec:")
    for name in names
        std.println(name)

fun test_vec_indexing()
    std.println("--- Vector Indexing ---")

    let numbers = [10, 20, 30, 40, 50]

    std.print("numbers[0] = ")
    std.println(numbers[0])

    std.print("numbers[1] = ")
    std.println(numbers[1])

    std.print("numbers[4] = ")
    std.println(numbers[4])

    let names = ["Alice", "Bob", "Charlie", "Diana"]

    std.print("names[0] = ")
    std.println(names[0])

    std.print("names[2] = ")
    std.println(names[2])

fun test_vec_functions()
    std.println("--- Vector Functions ---")

    let numbers = [10, 20, 30, 40, 50]

    # Sum vector elements
    mut total i32 = 0
    for n in numbers
        total = total + n
    std.print("sum = ")
    std.println(total)

    # Max of vector
    mut best = numbers[0]
    for n in numbers
        if n > best
            best = n
    std.print("max = ")
    std.println(best)

    # Min of vector
    mut worst = numbers[0]
    for n in numbers
        if n < worst
            worst = n
    std.print("min = ")
    std.println(worst)

fun test_empty_vec()
    std.println("--- Empty Vector ---")

    let empty = []
    std.print("empty vec length: ")

    # Count elements in empty vec
    mut count i32 = 0
    for e in empty
        count = count + 1
    std.println(count)

fun test_vec_bool()
    std.println("--- Vector of Booleans ---")

    let flags = [true, false, true, true, false]

    mut true_count i32 = 0
    for flag in flags
        if flag
            true_count = true_count + 1

    std.print("true count = ")
    std.println(true_count)

fun test_nested_vec_iteration()
    std.println("--- Nested Vector Iteration ---")

    let matrix = [[1, 2], [3, 4], [5, 6]]

    for row in matrix
        for cell in row
            std.println(cell)

pub fun main() i32
    test_vec_creation()
    test_vec_indexing()
    test_vec_functions()
    test_empty_vec()
    test_vec_bool()
    test_nested_vec_iteration()

    std.println("--- All vector tests passed ---")
    ret 0

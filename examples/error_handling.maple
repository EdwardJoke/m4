# Error Handling
# Demonstrates: error handling patterns with result types and guard checks

use io

fun divide(a i32, b i32)
    if b == 0
        io.println("Error: cannot divide by zero")
    else
        io.println(a / b)

fun safe_index(items, idx i32)
    mut count i32 = 0
    for item in items
        if count == idx
            ret item
        count = count + 1
    io.print("Error: index ")
    io.print(idx)
    io.println(" out of bounds")

pub fun main() i32
    io.println("--- Division with Error Checking ---")

    divide(10, 2)
    divide(10, 0)
    divide(15, 4)

    io.println("--- Safe Indexing ---")

    let items = ["a", "b", "c", "d", "e"]

    let idx0 = safe_index(items, 0)
    io.print("items[0] = ")
    io.println(idx0)

    let idx2 = safe_index(items, 2)
    io.print("items[2] = ")
    io.println(idx2)

    let idx10 = safe_index(items, 10)

    io.println("--- Nil for Optional Values ---")

    let maybe_val = nil
    io.print("nil value: ")
    io.println(maybe_val)

    ret 0

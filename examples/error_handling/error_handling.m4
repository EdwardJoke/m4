# Error Handling
# Demonstrates: error handling patterns with result types and guard checks

use std

fun divide(a i32, b i32)
    if b == 0
        std.println("Error: cannot divide by zero")
    else
        std.println(a / b)

fun safe_index(items, idx i32)
    mut count i32 = 0
    for item in items
        if count == idx
            ret item
        count = count + 1
    std.print("Error: index ")
    std.print(idx)
    std.println(" out of bounds")

pub fun main() i32
    std.println("--- Division with Error Checking ---")

    divide(10, 2)
    divide(10, 0)
    divide(15, 4)

    std.println("--- Safe Indexing ---")

    let items = ["a", "b", "c", "d", "e"]

    let idx0 = safe_index(items, 0)
    std.print("items[0] = ")
    std.println(idx0)

    let idx2 = safe_index(items, 2)
    std.print("items[2] = ")
    std.println(idx2)

    let idx10 = safe_index(items, 10)

    std.println("--- Nil for Optional Values ---")

    let maybe_val = nil
    std.print("nil value: ")
    std.println(maybe_val)

    ret 0

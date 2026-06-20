# Test: Error Handling
# Tests: nil, error patterns, safe indexing, guard checks

use std

fun divide_safe(a i32, b i32)
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

fun test_division_by_zero()
    std.println("--- Division by Zero ---")

    divide_safe(10, 2)
    divide_safe(10, 0)
    divide_safe(15, 4)

fun test_safe_indexing()
    std.println("--- Safe Indexing ---")

    let items = ["a", "b", "c", "d", "e"]

    let idx0 = safe_index(items, 0)
    std.print("items[0] = ")
    std.println(idx0)

    let idx2 = safe_index(items, 2)
    std.print("items[2] = ")
    std.println(idx2)

    let idx4 = safe_index(items, 4)
    std.print("items[4] = ")
    std.println(idx4)

    let idx10 = safe_index(items, 10)

    let neg_idx = safe_index(items, -1)

fun test_nil_values()
    std.println("--- nil Values ---")

    let maybe_val = nil
    std.print("nil value: ")
    std.println(maybe_val)

fun test_conditional_edge_cases()
    std.println("--- Conditional Edge Cases ---")

    # Zero in conditionals
    if 0
        std.println("0 is truthy (should NOT see)")
    else
        std.println("0 is falsy")

    if 1
        std.println("1 is truthy")

    if -1
        std.println("-1 is truthy")

    # Empty string
    let empty str = ""
    if empty
        std.println("empty string is truthy (should NOT see)")
    else
        std.println("empty string is falsy")

    # Non-empty string
    let nonempty str = "hi"
    if nonempty
        std.println("non-empty string is truthy")

fun test_safe_divide_with_result()
    std.println("--- Safe Divide Pattern ---")

    mut results i32 = 0
    if 10 / 2 == 5
        results = results + 1

    if 15 / 3 == 5
        results = results + 1

    if 7 / 2 == 3
        results = results + 1

    std.print("passed 3 division checks: ")
    std.println(results)

fun test_boolean_in_condition()
    std.println("--- Boolean in Condition ---")

    let t = true
    if t
        std.println("true in if works")

    let f = false
    if f
        std.println("false in if (should NOT print)")
    else
        std.println("false in else works")

pub fun main() i32
    test_division_by_zero()
    test_safe_indexing()
    test_nil_values()
    test_conditional_edge_cases()
    test_safe_divide_with_result()
    test_boolean_in_condition()

    std.println("--- All error handling tests passed ---")
    ret 0

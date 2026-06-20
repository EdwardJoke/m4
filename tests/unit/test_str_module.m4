# Test: str Module
# Tests: str.len, str.slice

use std
use str

fun test_str_len()
    std.println("--- str.len ---")

    let len1 = str.len("hello")
    std.print("len(hello) = ")
    std.println(len1)

    let len2 = str.len("")
    std.print("len(empty) = ")
    std.println(len2)

    let len3 = str.len("a")
    std.print("len(a) = ")
    std.println(len3)

    let len4 = str.len("Hello, World!")
    std.print("len(Hello World) = ")
    std.println(len4)

fun test_str_slice()
    std.println("--- str.slice ---")

    let s str = "hello"

    let slice1 = str.slice(s, 0, 2)
    std.print("slice(hello, 0, 2) = ")
    std.println(slice1)

    let slice2 = str.slice(s, 0, 5)
    std.print("slice(hello, 0, 5) = ")
    std.println(slice2)

    let slice3 = str.slice(s, 2, 5)
    std.print("slice(hello, 2, 5) = ")
    std.println(slice3)

    let slice4 = str.slice("Hello, World!", 7, 12)
    std.print("slice(Hello World, 7, 12) = ")
    std.println(slice4)

fun test_str_slice_edge_cases()
    std.println("--- str.slice edge cases ---")

    let s str = "abcdef"

    let slice1 = str.slice(s, 0, 1)
    std.print("first char: ")
    std.println(slice1)

    let slice2 = str.slice(s, 5, 6)
    std.print("last char: ")
    std.println(slice2)

    let slice3 = str.slice(s, 2, 4)
    std.print("middle: ")
    std.println(slice3)

    # Empty slice
    let slice4 = str.slice(s, 2, 2)
    std.print("empty slice: ")
    std.println(slice4)

fun test_str_len_with_slice()
    std.println("--- str.len + str.slice combo ---")

    let s str = "Hello, World!"

    let sliced = str.slice(s, 0, 5)
    let len = str.len(sliced)
    std.print("len of Hello slice: ")
    std.println(len)

pub fun main() i32
    test_str_len()
    test_str_slice()
    test_str_slice_edge_cases()
    test_str_len_with_slice()

    std.println("--- All str module tests passed ---")
    ret 0

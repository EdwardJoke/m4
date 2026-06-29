# Test: str Module
# Tests: str.len, str.slice

use std
use str

fun test_str_len() i32
    std.println("--- str.len ---")

    let len1 = str.len("hello")
    if len1 != 5
        std.println("FAIL: str.len(hello) expected 5, got ")
        std.println(len1)
        ret 1
    std.println("  PASS len(hello) = 5")

    let len2 = str.len("")
    if len2 != 0
        std.println("FAIL: str.len(empty) expected 0, got ")
        std.println(len2)
        ret 1
    std.println("  PASS len(empty) = 0")

    let len3 = str.len("a")
    if len3 != 1
        std.println("FAIL: str.len(a) expected 1, got ")
        std.println(len3)
        ret 1
    std.println("  PASS len(a) = 1")

    let len4 = str.len("Hello, World!")
    if len4 != 13
        std.println("FAIL: str.len(Hello World) expected 13, got ")
        std.println(len4)
        ret 1
    std.println("  PASS len(Hello World) = 13")

    ret 0

fun test_str_slice() i32
    std.println("--- str.slice ---")

    let s str = "hello"

    let slice1 = str.slice(s, 0, 2)
    if slice1 != "he"
        std.println("FAIL: slice(hello, 0, 2) expected 'he', got ")
        std.println(slice1)
        ret 1
    std.println("  PASS slice(hello, 0, 2) = he")

    let slice2 = str.slice(s, 0, 5)
    if slice2 != "hello"
        std.println("FAIL: slice(hello, 0, 5) expected 'hello', got ")
        std.println(slice2)
        ret 1
    std.println("  PASS slice(hello, 0, 5) = hello")

    let slice3 = str.slice(s, 2, 5)
    if slice3 != "llo"
        std.println("FAIL: slice(hello, 2, 5) expected 'llo', got ")
        std.println(slice3)
        ret 1
    std.println("  PASS slice(hello, 2, 5) = llo")

    let slice4 = str.slice("Hello, World!", 7, 12)
    if slice4 != "World"
        std.println("FAIL: slice(Hello World, 7, 12) expected 'World', got ")
        std.println(slice4)
        ret 1
    std.println("  PASS slice(Hello World, 7, 12) = World")

    ret 0

fun test_str_slice_edge_cases() i32
    std.println("--- str.slice edge cases ---")

    let s str = "abcdef"

    let slice1 = str.slice(s, 0, 1)
    if slice1 != "a"
        std.println("FAIL: first char expected 'a', got ")
        std.println(slice1)
        ret 1
    std.println("  PASS first char = a")

    let slice2 = str.slice(s, 5, 6)
    if slice2 != "f"
        std.println("FAIL: last char expected 'f', got ")
        std.println(slice2)
        ret 1
    std.println("  PASS last char = f")

    let slice3 = str.slice(s, 2, 4)
    if slice3 != "cd"
        std.println("FAIL: middle expected 'cd', got ")
        std.println(slice3)
        ret 1
    std.println("  PASS middle = cd")

    # Empty slice
    let slice4 = str.slice(s, 2, 2)
    if slice4 != ""
        std.println("FAIL: empty slice expected '', got ")
        std.println(slice4)
        ret 1
    std.println("  PASS empty slice = ''")

    ret 0

fun test_str_len_with_slice() i32
    std.println("--- str.len + str.slice combo ---")

    let s str = "Hello, World!"

    let sliced = str.slice(s, 0, 5)
    let len = str.len(sliced)
    if len != 5
        std.println("FAIL: len of Hello slice expected 5, got ")
        std.println(len)
        ret 1
    std.println("  PASS len of Hello slice = 5")

    ret 0

pub fun main() i32
    let failures = 0
    let r i32 = 0

    r = test_str_len()
    if r != 0
        failures = failures + 1
    r = test_str_slice()
    if r != 0
        failures = failures + 1
    r = test_str_slice_edge_cases()
    if r != 0
        failures = failures + 1
    r = test_str_len_with_slice()
    if r != 0
        failures = failures + 1

    if failures == 0
        std.println("--- All str module tests passed ---")
    else
        std.print("--- FAILED: ")
        std.print(failures)
        std.println(" test(s) failed ---")

    ret failures

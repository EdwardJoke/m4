# Test: thread Module
# Tests: thread.spawn, thread.join, thread.channel, thread.send, thread.recv
#
# Note: These tests verify concurrent execution and message passing.
# Threads run concurrently and results may arrive in any order.

use std
use thread

fun add_one(x i32) i32
    ret x + 1

fun add_two(a i32, b i32) i32
    ret a + b

fun multiply_three(a i32, b i32, c i32) i32
    ret a * b * c

fun test_spawn_join_basic() i32
    std.println("--- thread.spawn + thread.join basic ---")

    let handle = thread.spawn(add_one, 41)
    let result = thread.join(handle)
    std.print("add_one(41) = ")
    std.println(result)

    let handle2 = thread.spawn(add_two, 10, 20)
    let result2 = thread.join(handle2)
    std.print("add_two(10, 20) = ")
    std.println(result2)

    let handle3 = thread.spawn(multiply_three, 2, 3, 4)
    let result3 = thread.join(handle3)
    std.print("multiply_three(2, 3, 4) = ")
    std.println(result3)

    ret 0

fun test_channel_basic() i32
    std.println("--- thread.channel basic ---")

    let ch = thread.channel()

    let sent = thread.send(ch, 42)
    std.print("sent 42: ")
    std.println(sent)

    let received = thread.recv(ch)
    std.print("received: ")
    std.println(received)

    ret 0

fun test_channel_multiple_values() i32
    std.println("--- thread.channel multiple values ---")

    let ch = thread.channel()

    let s1 = thread.send(ch, 10)
    let s2 = thread.send(ch, 20)
    let s3 = thread.send(ch, 30)

    let r1 = thread.recv(ch)
    let r2 = thread.recv(ch)
    let r3 = thread.recv(ch)

    std.print("values: ")
    std.print(r1)
    std.print(", ")
    std.print(r2)
    std.print(", ")
    std.println(r3)

    ret 0

fun test_channel_different_types() i32
    std.println("--- thread.channel different types ---")

    let ch = thread.channel()

    let s1 = thread.send(ch, 100)
    let s2 = thread.send(ch, "hello")
    let s3 = thread.send(ch, true)

    let r1 = thread.recv(ch)
    let r2 = thread.recv(ch)
    let r3 = thread.recv(ch)

    std.print("int: ")
    std.println(r1)
    std.print("str: ")
    std.println(r2)
    std.print("bool: ")
    std.println(r3)

    ret 0

fun channel_worker(ch) i32
    thread.send(ch, 42)
    thread.send(ch, 99)
    thread.send(ch, "done")

    ret 0

fun test_spawn_with_channel() i32
    std.println("--- thread.spawn with channel ---")

    let ch = thread.channel()
    let handle = thread.spawn(channel_worker, ch)

    let r1 = thread.recv(ch)
    if r1 != 42
        std.println("FAIL: expected 42 from worker")
        ret 1

    let r2 = thread.recv(ch)
    if r2 != 99
        std.println("FAIL: expected 99 from worker")
        ret 1

    let r3 = thread.recv(ch)
    if r3 != "done"
        std.println("FAIL: expected 'done' from worker")
        ret 1

    let join_result = thread.join(handle)
    std.print("from worker via channel: ")
    std.print(r1)
    std.print(", ")
    std.print(r2)
    std.print(", ")
    std.println(r3)

    ret 0

pub fun main() i32
    mut failures i32 = 0

    failures = failures + test_spawn_join_basic()
    failures = failures + test_channel_basic()
    failures = failures + test_channel_multiple_values()
    failures = failures + test_channel_different_types()
    failures = failures + test_spawn_with_channel()

    if failures == 0
        std.println("--- All thread module tests passed ---")
    else
        std.print("--- FAILED: ")
        std.print(failures)
        std.println(" test(s) failed ---")

    ret failures

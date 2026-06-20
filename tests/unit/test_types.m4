# Test: All Primitive Types
# Tests every primitive type: i8, i16, i32, i64, u8, u32, u64, f32, f64, bool, str
# Tests: let, mut, type annotations, type inference

use std

fun test_integer_types()
    std.println("--- Integer Types ---")

    # i8 range: -128 to 127
    let a i8 = 100
    std.print("i8 = ")
    std.println(a)

    # i16 range: -32768 to 32767
    let b i16 = 32000
    std.print("i16 = ")
    std.println(b)

    # i32 default
    let c i32 = 100000
    std.print("i32 = ")
    std.println(c)

    # i64
    let d i64 = 10000000000
    std.print("i64 = ")
    std.println(d)

    # u8 range: 0 to 255
    let e u8 = 255
    std.print("u8 = ")
    std.println(e)

    # u32
    let f u32 = 4000000000
    std.print("u32 = ")
    std.println(f)

fun test_float_types()
    std.println("--- Float Types ---")

    # f32
    let g f32 = 3.14159
    std.print("f32 = ")
    std.println(g)

    # f64
    let h f64 = 2.718281828459
    std.print("f64 = ")
    std.println(h)

    # float arithmetic
    let pi f64 = 3.14159
    let e f64 = 2.71828
    std.print("pi + e = ")
    std.println(pi + e)
    std.print("pi * e = ")
    std.println(pi * e)
    std.print("pi / e = ")
    std.println(pi / e)
    std.print("pi - e = ")
    std.println(pi - e)

fun test_boolean_type()
    std.println("--- Boolean Type ---")

    let t bool = true
    let f bool = false

    std.print("true = ")
    std.println(t)

    std.print("false = ")
    std.println(f)

    std.print("true && true = ")
    std.println(t && t)

    std.print("true && false = ")
    std.println(t && f)

    std.print("true || false = ")
    std.println(t || f)

    std.print("false || false = ")
    std.println(f || f)

    std.print("!true = ")
    std.println(!t)

    std.print("!false = ")
    std.println(!f)

fun test_string_type()
    std.println("--- String Type ---")

    let greeting str = "Hello"
    let name str = "World"

    std.print("greeting = ")
    std.println(greeting)

    std.print("name = ")
    std.println(name)

    # String concatenation
    let combined str = greeting + ", " + name + "!"
    std.print("concat = ")
    std.println(combined)

    # String comparison
    let a str = "apple"
    let b str = "banana"
    let c str = "apple"

    std.print("a == c: ")
    std.println(a == c)

    std.print("a != b: ")
    std.println(a != b)

    std.print("a < b: ")
    std.println(a < b)

    std.print("b > a: ")
    std.println(b > a)

    std.print("a <= c: ")
    std.println(a <= c)

    std.print("b >= a: ")
    std.println(b >= a)

fun test_mutable_vars()
    std.println("--- Mutable Variables ---")

    mut counter i32 = 0
    counter = counter + 1
    counter = counter + 1
    counter = counter + 1

    std.print("counter after 3 increments: ")
    std.println(counter)

    mut msg str = "hello"
    msg = msg + " world"
    std.print("msg after append: ")
    std.println(msg)

fun test_type_inference()
    std.println("--- Type Inference ---")

    let inferred_int = 42
    let inferred_bool = false
    let inferred_str = "inferred"

    std.print("inferred int: ")
    std.println(inferred_int)

    std.print("inferred bool: ")
    std.println(inferred_bool)

    std.print("inferred str: ")
    std.println(inferred_str)

pub fun main() i32
    test_integer_types()
    test_float_types()
    test_boolean_type()
    test_string_type()
    test_mutable_vars()
    test_type_inference()

    std.println("--- All type tests passed ---")
    ret 0

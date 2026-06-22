# Types and Variables
# Demonstrates: all primitive types, let/mut, type annotations, type inference

use std

pub fun main() i32
    # Integer types
    let a i8 = 100
    let b i16 = 1000
    let c i32 = 100000
    let d i64 = 10000000000

    # Unsigned integer types
    let e u8 = 255
    let f u32 = 4000000000

    # Float types
    let g f32 = 3.14159
    let h f64 = 2.718281828459

    # Boolean
    let flag bool = true

    # String
    let greeting str = "Hello, m4!"

    # Type inference — no annotation needed
    let inferred = 42

    # Mutable variable
    mut counter i32 = 0
    counter = counter + 1
    counter = counter + 1

    # Print everything
    std.println(a)
    std.println(b)
    std.println(c)
    std.println(d)
    std.println(e)
    std.println(f)
    std.println(g)
    std.println(h)
    std.println(flag)
    std.println(greeting)
    std.println(inferred)
    std.println(counter)

    ret 0

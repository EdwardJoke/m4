# Types and Variables
# Demonstrates: all primitive types, let/mut, type annotations, type inference

use io

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
    io.println(a)
    io.println(b)
    io.println(c)
    io.println(d)
    io.println(e)
    io.println(f)
    io.println(g)
    io.println(h)
    io.println(flag)
    io.println(greeting)
    io.println(inferred)
    io.println(counter)

    ret 0

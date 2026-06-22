# Test: Structs
# Tests: type declarations, struct literals, field access, functions with structs

use std

type User
    name str
    age  i32

type Book
    title  str
    author str
    pages  i32

type Point
    x f64
    y f64

fun describe_user(u User)
    std.print(u.name)
    std.print(" is ")
    std.print(u.age)
    std.println(" years old")

fun is_adult(u User) bool
    if u.age >= 18
        ret true
    else
        ret false

fun describe_book(b Book)
    std.print("Book: ")
    std.print(b.title)
    std.print(" by ")
    std.print(b.author)
    std.print(" (")
    std.print(b.pages)
    std.println(" pages)")

fun distance_from_origin(p Point) f64
    let dx f64 = p.x
    let dy f64 = p.y
    ret dx * dx + dy * dy

fun test_struct_creation()
    std.println("--- Struct Creation ---")

    let alice User = User(
        name: "Alice"
        age: 30
    )

    let bob User = User(
        name: "Bob"
        age: 16
    )

    describe_user(alice)
    describe_user(bob)

fun test_struct_comparison()
    std.println("--- Struct Comparison ---")

    let alice User = User(
        name: "Alice"
        age: 30
    )

    if is_adult(alice)
        std.println("Alice is an adult")
    else
        std.println("Alice is NOT an adult")

    let bob User = User(
        name: "Bob"
        age: 16
    )

    if is_adult(bob)
        std.println("Bob is an adult")
    else
        std.println("Bob is NOT an adult")

fun test_struct_field_access()
    std.println("--- Struct Field Access ---")

    let fav_book Book = Book(
        title: "The m4 Language"
        author: "Edward"
        pages: 280
    )

    describe_book(fav_book)

    # Direct field access
    std.print("Title directly: ")
    std.println(fav_book.title)

    std.print("Author directly: ")
    std.println(fav_book.author)

    std.print("Pages directly: ")
    std.println(fav_book.pages)

fun test_struct_with_floats()
    std.println("--- Struct with Floats ---")

    let origin Point = Point(
        x: 3.0
        y: 4.0
    )

    let dist = distance_from_origin(origin)
    std.print("distance from origin (3,4): ")
    std.println(dist)

fun test_multiple_structs()
    std.println("--- Multiple Struct Instances ---")

    let book1 Book = Book(
        title: "m4 for Beginners"
        author: "Alice"
        pages: 200
    )

    let book2 Book = Book(
        title: "Advanced m4"
        author: "Bob"
        pages: 450
    )

    describe_book(book1)
    describe_book(book2)

    # Compare pages
    if book1.pages > book2.pages
        std.println("book1 has more pages")
    elif book1.pages < book2.pages
        std.println("book2 has more pages")
    else
        std.println("same number of pages")

pub fun main() i32
    test_struct_creation()
    test_struct_comparison()
    test_struct_field_access()
    test_struct_with_floats()
    test_multiple_structs()

    std.println("--- All struct tests passed ---")
    ret 0

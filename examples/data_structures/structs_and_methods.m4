# Structs and Methods
# Demonstrates: type declarations, struct literals, field access

use std

type User
    name str
    age  i32

type Book
    title  str
    author str
    pages  i32

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
    std.print(b.title)
    std.print(" by ")
    std.print(b.author)
    std.print(" (")
    std.print(b.pages)
    std.println(" pages)")

pub fun main() i32
    let alice User = User(
        name: "Alice"
        age: 30
    )
    let bob User = User(
        name: "Bob"
        age: 16
    )
    let fav_book Book = Book(
        title: "The m4 Language"
        author: "Edward"
        pages: 280
    )
    describe_user(alice)
    describe_user(bob)
    if is_adult(alice)
        std.println("Alice is an adult")
    else
        std.println("Alice is not an adult")
    if is_adult(bob)
        std.println("Bob is an adult")
    else
        std.println("Bob is not an adult")
    describe_book(fav_book)
    ret 0

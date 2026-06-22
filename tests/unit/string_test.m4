# String test program
use std

let greeting str = "Hello"
let name str = "World"

# Test printing strings
std.println(greeting)
std.println(name)

# Test concatenation
let combined str = greeting + " " + name
std.println(combined)

# Test string with numbers
let age i32 = 10
std.println(age)

# Test string comparison
let a str = "apple"
let b str = "banana"
std.println(a == b)
std.println(a != b)

# Test reading a string and printing
let input str = std.readln()
std.println("You said: ")
std.println(input)

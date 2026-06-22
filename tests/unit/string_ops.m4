use std

# Test string lexicographic comparison (gt/lt/gte/lte)
let a str = "apple"
let b str = "banana"

# a < b should be true
std.println("a < b:")
std.println(a < b)

# a > b should be false
std.println("a > b:")
std.println(a > b)

# a <= a should be true
std.println("a <= a:")
std.println(a <= a)

# b >= a should be true
std.println("b >= a:")
std.println(b >= a)

# Test string length via len() syntax
# For now let's just test what we have
std.println("done")

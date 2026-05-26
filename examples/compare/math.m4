use std

fun answer() i32
  ret 40 + 2

pub fun main()
  if answer() == 42
    std.println("math works")
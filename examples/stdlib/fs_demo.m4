# File System Demo
# Demonstrates: fs.read, fs.write, fs.exists, fs.delete

use std
use fs

pub fun main() i32
    std.println("=== File System Demo ===")

    # Write a file
    let filename str = "/tmp/m4_demo_file.txt"
    let content str = "Hello from m4!\nThis is a demo file."

    std.print("Writing to ")
    std.print(filename)
    std.print("... ")

    let w = fs.write(filename, content)
    if w
        std.println("OK")
    else
        std.println("FAILED")

    # Check it exists
    std.print("Checking file exists... ")
    let e = fs.exists(filename)
    if e
        std.println("YES")
    else
        std.println("NO")

    # Read it back
    std.println("Reading file:")
    let r = fs.read(filename)
    std.println(r)

    # Delete it
    std.print("Deleting file... ")
    let d = fs.delete(filename)
    if d
        std.println("OK")
    else
        std.println("FAILED")

    # Verify deletion
    std.print("Checking file gone... ")
    let e2 = fs.exists(filename)
    if e2
        std.println("NO (still exists!)")
    else
        std.println("YES (properly deleted)")

    std.println("=== FS Demo Complete ===")

    ret 0

use std

# Build a string by repeated concatenation in a loop
# This stresses the VM's binaryOp .add for strings (alloc + copy each iteration)

fun build_str(n i32) str
    mut s str = ""
    for i in std.range(0, n)
        s = s + "a"
    ret s

pub fun main()
    # Test 1: 500 iterations
    std.print("n=500: ")
    let s500 str = build_str(500)
    std.println("done (len=500)")

    # Test 2: 2000 iterations
    std.print("n=2000: ")
    let s2000 str = build_str(2000)
    std.println("done (len=2000)")

    # Test 3: 5000 iterations
    std.print("n=5000: ")
    let s5000 str = build_str(5000)
    std.println("done (len=5000)")

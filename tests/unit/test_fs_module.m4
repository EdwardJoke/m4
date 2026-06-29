# Test: fs Module
# Tests: fs.write, fs.read, fs.exists, fs.delete

use std
use fs

fun test_fs_write_read() i32
    mut fail i32 = 0
    std.println("--- fs.write and fs.read ---")

    let content str = "Hello from m4 filesystem test!"

    # Write file
    let written = fs.write("/tmp/m4_test_file.txt", content)
    if written
        std.println("fs.write: success")
    else
        std.println("fs.write: FAILED")
        fail = fail + 1

    # Check it exists
    let exists = fs.exists("/tmp/m4_test_file.txt")
    if exists
        std.println("fs.exists: file exists")
    else
        std.println("fs.exists: FAILED")
        fail = fail + 1

    # Read it back
    let read_content = fs.read("/tmp/m4_test_file.txt")
    std.print("fs.read: ")
    std.println(read_content)

    # Delete it
    let deleted = fs.delete("/tmp/m4_test_file.txt")
    if deleted
        std.println("fs.delete: success")
    else
        std.println("fs.delete: FAILED")
        fail = fail + 1

    # Verify it's gone
    let exists_after = fs.exists("/tmp/m4_test_file.txt")
    if exists_after
        std.println("fs.exists after delete: FAILED (file still exists)")
        fail = fail + 1
    else
        std.println("fs.exists after delete: file properly removed")

    ret fail

fun test_fs_nonexistent() i32
    std.println("--- fs.read nonexistent file ---")

    let content = fs.read("/tmp/m4_nonexistent_file_xyz.txt")
    std.print("reading nonexistent file: ")
    std.println(content)

    ret 0

fun test_fs_exists_nonexistent() i32
    std.println("--- fs.exists nonexistent ---")

    let exists = fs.exists("/tmp/m4_nonexistent_file_xyz.txt")
    std.print("nonexistent file exists? ")
    std.println(exists)

    ret 0

fun test_fs_write_multiple() i32
    mut fail i32 = 0
    std.println("--- fs.write multiple files ---")

    let w1 = fs.write("/tmp/m4_test_a.txt", "File A content")
    if w1
        std.println("wrote file A")
    else
        std.println("FAILED to write file A")
        fail = fail + 1

    let w2 = fs.write("/tmp/m4_test_b.txt", "File B content")
    if w2
        std.println("wrote file B")
    else
        std.println("FAILED to write file B")
        fail = fail + 1

    # Read back
    let r1 = fs.read("/tmp/m4_test_a.txt")
    std.print("file A: ")
    std.println(r1)

    let r2 = fs.read("/tmp/m4_test_b.txt")
    std.print("file B: ")
    std.println(r2)

    # Clean up
    let d1 = fs.delete("/tmp/m4_test_a.txt")
    if d1
        std.println("deleted file A")
    else
        std.println("FAILED to delete file A")
        fail = fail + 1

    let d2 = fs.delete("/tmp/m4_test_b.txt")
    if d2
        std.println("deleted file B")
    else
        std.println("FAILED to delete file B")
        fail = fail + 1

    ret fail

fun test_fs_delete_nonexistent() i32
    std.println("--- fs.delete nonexistent ---")

    let deleted = fs.delete("/tmp/m4_nonexistent_delete_test.txt")
    std.print("delete nonexistent file: ")
    std.println(deleted)

    ret 0

pub fun main() i32
    let failures = 0

    failures = failures + test_fs_write_read()
    failures = failures + test_fs_nonexistent()
    failures = failures + test_fs_exists_nonexistent()
    failures = failures + test_fs_write_multiple()
    failures = failures + test_fs_delete_nonexistent()

    if failures == 0
        std.println("--- All fs module tests passed ---")
    else
        std.print("--- FAILED: ")
        std.print(failures)
        std.println(" test(s) failed ---")

    ret failures

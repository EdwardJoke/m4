const zig_std = @import("std");
const VM = @import("../compiler/vm.zig");
const value = @import("../compiler/value.zig");

/// Register all str module native functions (len, slice) with the VM.
pub fn register(vm: *VM) !void {
    try vm.registerNative("str.len", @ptrCast(@constCast(&strLen)));
    try vm.registerNative("str.slice", @ptrCast(@constCast(&strSlice)));
}

/// Return the byte length of a string. Returns 0 for non-string arguments.
fn strLen(_: *VM, args: []const value.Value) value.Value {
    if (args.len < 1) return .{ .int = 0 };
    const len: i64 = switch (args[0]) {
        .string => |s| @intCast(s.len),
        else => 0,
    };
    return .{ .int = len };
}

/// Extract a substring via byte-level slicing (start inclusive, end exclusive). Returns nil on out-of-bounds or bad args.
fn strSlice(vm: *VM, args: []const value.Value) value.Value {
    if (args.len < 3) return .nil;
    const s = switch (args[0]) {
        .string => |str| str,
        else => return .nil,
    };
    const start = switch (args[1]) {
        .int => |i| i,
        else => return .nil,
    };
    const end = switch (args[2]) {
        .int => |i| i,
        else => return .nil,
    };
    if (start < 0 or end < 0) return .nil;
    const ustart: usize = @intCast(start);
    const uend: usize = @intCast(end);
    if (ustart > s.len or uend > s.len or ustart > uend) return .nil;
    const sliced = vm.allocator.dupe(u8, s[ustart..uend]) catch return .nil;
    return .{ .string = sliced };
}

test "str.len" {
    var vm = VM.init(zig_std.testing.allocator);
    defer vm.deinit();

    var vm2 = VM.init(zig_std.testing.allocator);
    defer vm2.deinit();

    // normal string
    const r = strLen(&vm, &.{.{ .string = "hello" }});
    try zig_std.testing.expectEqual(@as(i64, 5), r.int);

    // empty string
    const r2 = strLen(&vm, &.{.{ .string = "" }});
    try zig_std.testing.expectEqual(@as(i64, 0), r2.int);

    // no args → 0
    const r3 = strLen(&vm, &.{});
    try zig_std.testing.expectEqual(@as(i64, 0), r3.int);

    // non-string → 0
    const r4 = strLen(&vm2, &.{.{ .int = 42 }});
    try zig_std.testing.expectEqual(@as(i64, 0), r4.int);
}

test "str.slice" {
    var vm = VM.init(zig_std.testing.allocator);
    defer vm.deinit();

    var vm2 = VM.init(zig_std.testing.allocator);
    defer vm2.deinit();

    // normal slice
    const r = strSlice(&vm, &.{ .{ .string = "hello" }, .{ .int = 0 }, .{ .int = 2 } });
    defer if (r == .string) vm.allocator.free(r.string);
    try zig_std.testing.expectEqualStrings("he", r.string);

    // full string
    const r2 = strSlice(&vm, &.{ .{ .string = "world" }, .{ .int = 0 }, .{ .int = 5 } });
    defer if (r2 == .string) vm.allocator.free(r2.string);
    try zig_std.testing.expectEqualStrings("world", r2.string);

    // middle slice
    const r3 = strSlice(&vm2, &.{ .{ .string = "abcdef" }, .{ .int = 2 }, .{ .int = 5 } });
    defer vm2.allocator.free(r3.string);
    try zig_std.testing.expectEqualStrings("cde", r3.string);

    // start > end → nil
    const r4 = strSlice(&vm, &.{ .{ .string = "abc" }, .{ .int = 2 }, .{ .int = 1 } });
    try zig_std.testing.expect(r4 == .nil);

    // out of bounds → nil
    const r5 = strSlice(&vm, &.{ .{ .string = "abc" }, .{ .int = 0 }, .{ .int = 10 } });
    try zig_std.testing.expect(r5 == .nil);

    // negative start → nil
    const r6 = strSlice(&vm, &.{ .{ .string = "abc" }, .{ .int = -1 }, .{ .int = 2 } });
    try zig_std.testing.expect(r6 == .nil);

    // not enough args → nil
    const r7 = strSlice(&vm, &.{.{ .string = "abc" }});
    try zig_std.testing.expect(r7 == .nil);

    // non-string first arg → nil
    const r8 = strSlice(&vm, &.{ .{ .int = 42 }, .{ .int = 0 }, .{ .int = 2 } });
    try zig_std.testing.expect(r8 == .nil);
}

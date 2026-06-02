const zig_std = @import("std");
const VM = @import("../vm.zig");
const value = @import("../value.zig");

pub fn register(vm: *VM) !void {
    try vm.registerNative("str.len", @constCast(@ptrCast(&strLen)));
    try vm.registerNative("str.slice", @constCast(@ptrCast(&strSlice)));
}

fn strLen(_: *VM, args: []const value.Value) value.Value {
    if (args.len < 1) return .{ .int = 0 };
    const len: i64 = switch (args[0]) {
        .string => |s| @intCast(s.len),
        else => 0,
    };
    return .{ .int = len };
}

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

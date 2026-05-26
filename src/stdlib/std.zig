const zig_std = @import("std");
const posix = zig_std.posix;
const VM = @import("../vm.zig");
const value = @import("../value.zig");

const VecObj = struct {
    items: zig_std.ArrayList(value.Value),
};

pub fn register(vm: *VM) !void {
    try vm.registerNative("std.println", @constCast(@ptrCast(&println)));
    try vm.registerNative("std.print", @constCast(@ptrCast(&print)));
    try vm.registerNative("std.readln", @constCast(@ptrCast(&readln)));
    try vm.registerNative("std.read", @constCast(@ptrCast(&readAll)));
    try vm.registerNative("std.readChar", @constCast(@ptrCast(&readChar)));
    try vm.registerNative("std.range", @constCast(@ptrCast(&range)));
}

fn println(_: *VM, args: []const value.Value) value.Value {
    for (args) |arg| writeValue(arg);
    zig_std.debug.print("\n", .{});
    return .nil;
}

fn print(_: *VM, args: []const value.Value) value.Value {
    for (args) |arg| writeValue(arg);
    return .nil;
}

fn readln(vm: *VM, _: []const value.Value) value.Value {
    var buf = zig_std.ArrayList(u8).empty;
    var byte: [1]u8 = undefined;
    while (true) {
        const n = posix.read(posix.STDIN_FILENO, &byte) catch |err| {
            zig_std.debug.print("std.readln error: {}\n", .{err});
            return .nil;
        };
        if (n == 0) break;
        if (byte[0] == '\n') break;
        buf.append(vm.allocator, byte[0]) catch |err| {
            zig_std.debug.print("std.readln error: {}\n", .{err});
            return .nil;
        };
    }
    return .{ .string = buf.items };
}

fn readAll(vm: *VM, _: []const value.Value) value.Value {
    var buf = zig_std.ArrayList(u8).empty;
    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = posix.read(posix.STDIN_FILENO, &chunk) catch |err| {
            zig_std.debug.print("std.read error: {}\n", .{err});
            return .nil;
        };
        if (n == 0) break;
        buf.appendSlice(vm.allocator, chunk[0..n]) catch |err| {
            zig_std.debug.print("std.read error: {}\n", .{err});
            return .nil;
        };
    }
    return .{ .string = buf.items };
}

fn readChar(_: *VM, _: []const value.Value) value.Value {
    var buf: [4]u8 = [_]u8{0} ** 4;
    const n = posix.read(posix.STDIN_FILENO, buf[0..1]) catch |err| {
        zig_std.debug.print("std.readChar error: {}\n", .{err});
        return .nil;
    };
    if (n == 0) return .{ .char = 0 };
    const len: u3 = if (buf[0] < 0x80) @as(u3, 1) else if (buf[0] < 0xE0) @as(u3, 2) else if (buf[0] < 0xF0) @as(u3, 3) else @as(u3, 4);
    if (len > 1) {
        const m = posix.read(posix.STDIN_FILENO, buf[1..len]) catch |err| {
            zig_std.debug.print("std.readChar error: {}\n", .{err});
            return .nil;
        };
        if (m < len - 1) return .{ .char = buf[0] };
    }
    const cp: u21 = switch (len) {
        1 => buf[0],
        2 => (@as(u21, buf[0] & 0x1F) << 6) | (buf[1] & 0x3F),
        3 => (@as(u21, buf[0] & 0x0F) << 12) | (@as(u21, buf[1] & 0x3F) << 6) | (buf[2] & 0x3F),
        4 => (@as(u21, buf[0] & 0x07) << 18) | (@as(u21, buf[1] & 0x3F) << 12) | (@as(u21, buf[2] & 0x3F) << 6) | (buf[3] & 0x3F),
        else => unreachable,
    };
    return .{ .char = cp };
}

fn range(vm: *VM, args: []const value.Value) value.Value {
    if (args.len < 2) return .nil;

    const start = switch (args[0]) {
        .int => |i| i,
        else => return .nil,
    };
    const end = switch (args[1]) {
        .int => |i| i,
        else => return .nil,
    };

    const count: usize = if (end > start) @intCast(end - start) else 0;

    const vec = vm.allocator.create(VecObj) catch return .nil;
    vec.items = zig_std.ArrayList(value.Value).initCapacity(vm.allocator, count) catch return .nil;

    var i: i64 = start;
    while (i < end) : (i += 1) {
        vec.items.appendAssumeCapacity(.{ .int = i });
    }

    return .{ .vec = vec };
}

fn writeValue(arg: value.Value) void {
    switch (arg) {
        .int => |i| zig_std.debug.print("{d}", .{i}),
        .float => |f| zig_std.debug.print("{d}", .{f}),
        .bool => |b| zig_std.debug.print("{}", .{b}),
        .string => |s| zig_std.debug.print("{s}", .{s}),
        .nil => zig_std.debug.print("nil", .{}),
        .char => |c| zig_std.debug.print("{u}", .{c}),
        else => zig_std.debug.print("<value>", .{}),
    }
}

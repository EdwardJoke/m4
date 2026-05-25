const std = @import("std");
const posix = std.posix;
const VM = @import("../vm.zig");
const value = @import("../value.zig");

pub fn register(vm: *VM) !void {
    try vm.registerNative("io.println", @constCast(@ptrCast(&println)));
    try vm.registerNative("io.print", @constCast(@ptrCast(&print)));
    try vm.registerNative("io.readln", @constCast(@ptrCast(&readln)));
    try vm.registerNative("io.read", @constCast(@ptrCast(&readAll)));
    try vm.registerNative("io.readChar", @constCast(@ptrCast(&readChar)));
}

fn println(_: *VM, args: []const value.Value) value.Value {
    for (args) |arg| writeValue(arg);
    std.debug.print("\n", .{});
    return .nil;
}

fn print(_: *VM, args: []const value.Value) value.Value {
    for (args) |arg| writeValue(arg);
    return .nil;
}

fn readln(vm: *VM, _: []const value.Value) value.Value {
    var buf = std.ArrayList(u8).empty;
    var byte: [1]u8 = undefined;
    while (true) {
        const n = posix.read(posix.STDIN_FILENO, &byte) catch |err| {
            std.debug.print("io.readln error: {}\n", .{err});
            return .nil;
        };
        if (n == 0) break;
        if (byte[0] == '\n') break;
        buf.append(vm.allocator, byte[0]) catch |err| {
            std.debug.print("io.readln error: {}\n", .{err});
            return .nil;
        };
    }
    return .{ .string = buf.items };
}

fn readAll(vm: *VM, _: []const value.Value) value.Value {
    var buf = std.ArrayList(u8).empty;
    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = posix.read(posix.STDIN_FILENO, &chunk) catch |err| {
            std.debug.print("io.read error: {}\n", .{err});
            return .nil;
        };
        if (n == 0) break;
        buf.appendSlice(vm.allocator, chunk[0..n]) catch |err| {
            std.debug.print("io.read error: {}\n", .{err});
            return .nil;
        };
    }
    return .{ .string = buf.items };
}

fn readChar(_: *VM, _: []const value.Value) value.Value {
    var buf: [4]u8 = [_]u8{0} ** 4;
    const n = posix.read(posix.STDIN_FILENO, buf[0..1]) catch |err| {
        std.debug.print("io.readChar error: {}\n", .{err});
        return .nil;
    };
    if (n == 0) return .{ .char = 0 };
    const len: u3 = if (buf[0] < 0x80) @as(u3, 1) else if (buf[0] < 0xE0) @as(u3, 2) else if (buf[0] < 0xF0) @as(u3, 3) else @as(u3, 4);
    if (len > 1) {
        const m = posix.read(posix.STDIN_FILENO, buf[1..len]) catch |err| {
            std.debug.print("io.readChar error: {}\n", .{err});
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

fn writeValue(arg: value.Value) void {
    switch (arg) {
        .int => |i| std.debug.print("{d}", .{i}),
        .float => |f| std.debug.print("{d}", .{f}),
        .bool => |b| std.debug.print("{}", .{b}),
        .string => |s| std.debug.print("{s}", .{s}),
        .nil => std.debug.print("nil", .{}),
        .char => |c| std.debug.print("{u}", .{c}),
        else => std.debug.print("<value>", .{}),
    }
}

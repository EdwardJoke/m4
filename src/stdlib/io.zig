const std = @import("std");
const VM = @import("../vm.zig");
const value = @import("../value.zig");

pub fn register(vm: *VM) !void {
    try vm.registerNative("io.println", @constCast(@ptrCast(&println)));
    try vm.registerNative("io.print", @constCast(@ptrCast(&print)));
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

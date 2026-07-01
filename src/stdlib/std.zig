const zig_std = @import("std");
const posix = zig_std.posix;
const Io = zig_std.Io;
const VM = @import("../compiler/vm.zig");
const value = @import("../compiler/value.zig");

const VecObj = struct {
    items: zig_std.ArrayList(value.Value),
};

/// Register all std module native functions (println, print, readln, read, readChar, range) with the VM.
pub fn register(vm: *VM) !void {
    try vm.registerNative("std.println", @ptrCast(@constCast(&println)));
    try vm.registerNative("std.print", @ptrCast(@constCast(&print)));
    try vm.registerNative("std.readln", @ptrCast(@constCast(&readln)));
    try vm.registerNative("std.read", @ptrCast(@constCast(&readAll)));
    try vm.registerNative("std.readChar", @ptrCast(@constCast(&readChar)));
    try vm.registerNative("std.range", @ptrCast(@constCast(&range)));
}

/// Print each argument to stdout followed by a newline. Returns nil.
fn println(_: *VM, args: []const value.Value) value.Value {
    for (args) |arg| writeValue(arg);
    const io = Io.Threaded.global_single_threaded.io();
    const out = Io.File.stdout();
    Io.File.writeStreamingAll(out, io, "\n") catch {};
    return .nil;
}

/// Print each argument to stdout without a trailing newline. Returns nil.
fn print(_: *VM, args: []const value.Value) value.Value {
    for (args) |arg| writeValue(arg);
    return .nil;
}

/// Read a single line from stdin (up to newline). Returns the line as a string, or nil on error.
fn readln(vm: *VM, _: []const value.Value) value.Value {
    var buf = zig_std.ArrayList(u8).empty;
    defer buf.deinit(vm.allocator);
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
    // Copy to an independently-owned allocation and track it in the VM
    const str = vm.allocator.dupe(u8, buf.items) catch return .nil;
    vm.allocated_strings.append(vm.allocator, str) catch {
        vm.allocator.free(str);
        return .nil;
    };
    return .{ .string = str };
}

/// Read all remaining data from stdin until EOF. Returns the data as a string, or nil on error.
fn readAll(vm: *VM, _: []const value.Value) value.Value {
    var buf = zig_std.ArrayList(u8).empty;
    defer buf.deinit(vm.allocator);
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
    // Copy to an independently-owned allocation and track it in the VM
    const str = vm.allocator.dupe(u8, buf.items) catch return .nil;
    vm.allocated_strings.append(vm.allocator, str) catch {
        vm.allocator.free(str);
        return .nil;
    };
    return .{ .string = str };
}

/// Read a single UTF-8 character from stdin. Returns the character, or 0 on EOF.
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

/// Generate a vec of integers from start (inclusive) to end (exclusive). Returns nil on bad args.
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
    var buf: [256]u8 = undefined;
    const s = switch (arg) {
        .int => |i| zig_std.fmt.bufPrint(&buf, "{d}", .{i}) catch " overflow",
        .float => |f| zig_std.fmt.bufPrint(&buf, "{d}", .{f}) catch " overflow",
        .bool => |b| zig_std.fmt.bufPrint(&buf, "{}", .{b}) catch " overflow",
        .string => |s| s,
        .nil => "nil",
        .char => |c| zig_std.fmt.bufPrint(&buf, "{u}", .{c}) catch " overflow",
        else => "<value>",
    };
    const io = Io.Threaded.global_single_threaded.io();
    const out = Io.File.stdout();
    Io.File.writeStreamingAll(out, io, s) catch {};
}

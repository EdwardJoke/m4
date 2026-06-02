const zig_std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
});

const VM = @import("../vm.zig");
const value = @import("../value.zig");

pub fn register(vm: *VM) !void {
    try vm.registerNative("fs.read", @constCast(@ptrCast(&fsRead)));
    try vm.registerNative("fs.write", @constCast(@ptrCast(&fsWrite)));
    try vm.registerNative("fs.exists", @constCast(@ptrCast(&fsExists)));
    try vm.registerNative("fs.delete", @constCast(@ptrCast(&fsDelete)));
}

fn fsRead(vm: *VM, args: []const value.Value) value.Value {
    if (args.len < 1) return .nil;
    const path = switch (args[0]) {
        .string => |s| s,
        else => return .nil,
    };
    const path_z = vm.allocator.dupeZ(u8, path) catch return .nil;
    defer vm.allocator.free(path_z);
    const file = c.fopen(path_z, "rb");
    if (file == null) return .nil;
    defer _ = c.fclose(file);
    if (c.fseek(file, 0, c.SEEK_END) != 0) return .nil;
    const size = c.ftell(file);
    if (size < 0) return .nil;
    if (c.fseek(file, 0, c.SEEK_SET) != 0) return .nil;
    const buf = vm.allocator.alloc(u8, @intCast(size)) catch return .nil;
    const n = c.fread(buf.ptr, 1, buf.len, file);
    if (n != buf.len) {
        vm.allocator.free(buf);
        return .nil;
    }
    return .{ .string = buf[0..n] };
}

fn fsWrite(vm: *VM, args: []const value.Value) value.Value {
    if (args.len < 2) return .{ .bool = false };
    const path = switch (args[0]) {
        .string => |s| s,
        else => return .{ .bool = false },
    };
    const data = switch (args[1]) {
        .string => |s| s,
        else => return .{ .bool = false },
    };
    const path_z = vm.allocator.dupeZ(u8, path) catch return .{ .bool = false };
    defer vm.allocator.free(path_z);
    const file = c.fopen(path_z, "wb");
    if (file == null) return .{ .bool = false };
    defer _ = c.fclose(file);
    const n = c.fwrite(data.ptr, 1, data.len, file);
    return .{ .bool = n == data.len };
}

fn fsExists(vm: *VM, args: []const value.Value) value.Value {
    if (args.len < 1) return .{ .bool = false };
    const path = switch (args[0]) {
        .string => |s| s,
        else => return .{ .bool = false },
    };
    const path_z = vm.allocator.dupeZ(u8, path) catch return .{ .bool = false };
    defer vm.allocator.free(path_z);
    var st: c.struct_stat = undefined;
    const rc = c.stat(path_z, &st);
    return .{ .bool = rc == 0 };
}

fn fsDelete(vm: *VM, args: []const value.Value) value.Value {
    if (args.len < 1) return .{ .bool = false };
    const path = switch (args[0]) {
        .string => |s| s,
        else => return .{ .bool = false },
    };
    const path_z = vm.allocator.dupeZ(u8, path) catch return .{ .bool = false };
    defer vm.allocator.free(path_z);
    const rc = c.remove(path_z);
    return .{ .bool = rc == 0 };
}

test "fs.write + fs.read + fs.exists + fs.delete" {
    var vm = VM.init(zig_std.testing.allocator);
    defer vm.deinit();

    const test_path = ".wasup/_fs_test_tmp.txt";

    // write
    const w = fsWrite(&vm, &.{ .{ .string = test_path }, .{ .string = "hello fs!" } });
    try zig_std.testing.expect(w.bool);

    // exists
    const e = fsExists(&vm, &.{.{ .string = test_path }});
    try zig_std.testing.expect(e.bool);

    // read
    const r = fsRead(&vm, &.{.{ .string = test_path }});
    defer if (r == .string) vm.allocator.free(r.string);
    try zig_std.testing.expectEqualStrings("hello fs!", r.string);

    // delete
    const d = fsDelete(&vm, &.{.{ .string = test_path }});
    try zig_std.testing.expect(d.bool);

    // exists after delete → false
    const e2 = fsExists(&vm, &.{.{ .string = test_path }});
    try zig_std.testing.expect(!e2.bool);
}

test "fs.read nonexistent" {
    var vm = VM.init(zig_std.testing.allocator);
    defer vm.deinit();

    const r = fsRead(&vm, &.{.{ .string = "/nonexistent/path/xyz123_nope" }});
    try zig_std.testing.expect(r == .nil);
}

test "fs.write with bad args" {
    var vm = VM.init(zig_std.testing.allocator);
    defer vm.deinit();

    // no args → false
    const w = fsWrite(&vm, &.{});
    try zig_std.testing.expect(!w.bool);

    // only path → false
    const w2 = fsWrite(&vm, &.{.{ .string = "/tmp/x" }});
    try zig_std.testing.expect(!w2.bool);
}

test "fs.exists nonexistent" {
    var vm = VM.init(zig_std.testing.allocator);
    defer vm.deinit();

    const e = fsExists(&vm, &.{.{ .string = "/nonexistent/path/xyz123_nope" }});
    try zig_std.testing.expect(!e.bool);
}

test "fs.delete nonexistent" {
    var vm = VM.init(zig_std.testing.allocator);
    defer vm.deinit();

    const d = fsDelete(&vm, &.{.{ .string = "/nonexistent/path/xyz123_nope" }});
    try zig_std.testing.expect(!d.bool);
}

const zig_std = @import("std");
const c = @cImport({
    @cDefine("_GNU_SOURCE", {});
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
    _ = c.fseek(file, 0, c.SEEK_END);
    const size = c.ftell(file);
    _ = c.fseek(file, 0, c.SEEK_SET);
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

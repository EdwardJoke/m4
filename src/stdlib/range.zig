const std = @import("std");
const VM = @import("../vm.zig");
const value = @import("../value.zig");

const VecObj = struct {
    items: std.ArrayList(value.Value),
};

pub fn register(vm: *VM) !void {
    try vm.registerNative("range.range", @constCast(@ptrCast(&range)));
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
    vec.items = std.ArrayList(value.Value).initCapacity(vm.allocator, count) catch return .nil;

    var i: i64 = start;
    while (i < end) : (i += 1) {
        vec.items.appendAssumeCapacity(.{ .int = i });
    }

    return .{ .vec = vec };
}

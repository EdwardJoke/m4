const std = @import("std");
const Io = std.Io;

pub fn run(io: Io, allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;
    _ = allocator;
    const cwd = std.Io.Dir.cwd();

    std.Io.Dir.deleteTree(cwd, io, ".m4_cache") catch |err| switch (err) {
        error.FileNotFound => {},
        else => |e| return e,
    };
    std.debug.print("mein clean: removed .m4_cache\n", .{});

    std.Io.Dir.deleteTree(cwd, io, "zig-out") catch |err| switch (err) {
        error.FileNotFound => {},
        else => |e| return e,
    };
    std.debug.print("mein clean: removed zig-out/\n", .{});

    std.Io.Dir.deleteTree(cwd, io, ".zig-cache") catch |err| switch (err) {
        error.FileNotFound => {},
        else => |e| return e,
    };
    std.debug.print("mein clean: removed .zig-cache\n", .{});
}

const std = @import("std");
const Io = std.Io;

pub fn run(io: Io, allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;
    const result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "rm", "-rf", ".m4_cache" },
    });
    allocator.free(result.stdout);
    allocator.free(result.stderr);
    std.debug.print("mein clean: removed .m4_cache\n", .{});
}

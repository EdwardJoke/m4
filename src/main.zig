const std = @import("std");
const cli = @import("cli.zig");

pub fn main(init: std.process.Init) void {
    cli.run(init) catch |err| {
        switch (err) {
            error.InvalidFlag => {},
            else => std.debug.print("error: {}\n", .{err}),
        }
        std.process.exit(1);
    };
}

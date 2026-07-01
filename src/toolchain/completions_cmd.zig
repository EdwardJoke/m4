const std = @import("std");

const m4c_bash = @embedFile("completions/m4c.bash");
const m4c_zsh = @embedFile("completions/m4c.zsh");
const mein_bash = @embedFile("completions/mein.bash");
const mein_zsh = @embedFile("completions/mein.zsh");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = io;
    _ = allocator;
    const shell = if (args.len > 0) args[0] else "bash";
    const bin = if (args.len > 1) args[1] else "mein";

    const script = if (std.mem.eql(u8, bin, "m4c"))
        if (std.mem.eql(u8, shell, "zsh")) m4c_zsh else m4c_bash
    else
        if (std.mem.eql(u8, shell, "zsh")) mein_zsh else mein_bash;

    std.debug.print("{s}", .{script});
}

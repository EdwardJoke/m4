const std = @import("std");
const Io = std.Io;
const init_cmd = @import("init_cmd.zig");
const clean_cmd = @import("clean_cmd.zig");

const VERSION = "0.4.0";

const Command = struct {
    name: []const u8,
    aliases: []const []const u8,
    runFn: *const fn (io: Io, allocator: std.mem.Allocator, args: []const []const u8) anyerror!void,
    description: []const u8,
};

const commands = [_]Command{
    .{
        .name = "init",
        .aliases = &.{"new"},
        .runFn = init_cmd.run,
        .description = "Initialize a new m4 project",
    },
    .{
        .name = "clean",
        .aliases = &.{},
        .runFn = clean_cmd.run,
        .description = "Clean build artifacts and caches",
    },
};

fn printUsage() void {
    std.debug.print(
        \\mein v{s} — m4 toolchain manager
        \\
        \\Usage:
        \\  mein <command> [options]
        \\
        \\Commands:
        \\
    , .{VERSION});
    for (&commands) |cmd| {
        var name_buf: [64]u8 = undefined;
        var name_len: usize = @intCast(cmd.name.len);
        @memcpy(name_buf[0..name_len], cmd.name);
        for (cmd.aliases) |alias| {
            if (name_len + 2 + alias.len > name_buf.len) break;
            name_buf[name_len] = ',';
            name_buf[name_len + 1] = ' ';
            @memcpy(name_buf[name_len + 2 .. name_len + 2 + alias.len], alias);
            name_len += 2 + alias.len;
        }
        std.debug.print("  {s}    {s}\n", .{ name_buf[0..name_len], cmd.description });
    }
    std.debug.print(
        \\  help          Show this help
        \\
    , .{});
}

pub fn main(init: std.process.Init) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = init.minimal.args.toSlice(arena) catch {
        printUsage();
        std.process.exit(1);
    };

    if (args.len < 2) {
        printUsage();
        return;
    }

    const subcmd = args[1];

    if (std.mem.eql(u8, subcmd, "help")) {
        printUsage();
        return;
    }

    for (&commands) |cmd| {
        if (std.mem.eql(u8, subcmd, cmd.name)) {
            const cmd_args = if (args.len > 2) args[2..] else &.{};
            cmd.runFn(io, arena, cmd_args) catch |err| {
                std.debug.print("error: {}\n", .{err});
                std.process.exit(1);
            };
            return;
        }
        for (cmd.aliases) |alias| {
            if (std.mem.eql(u8, subcmd, alias)) {
                const cmd_args = if (args.len > 2) args[2..] else &.{};
                cmd.runFn(io, arena, cmd_args) catch |err| {
                    std.debug.print("error: {}\n", .{err});
                    std.process.exit(1);
                };
                return;
            }
        }
    }

    std.debug.print("mein: unknown command '{s}'\n", .{subcmd});
    std.debug.print("Run 'mein help' for usage.\n", .{});
    std.process.exit(1);
}
